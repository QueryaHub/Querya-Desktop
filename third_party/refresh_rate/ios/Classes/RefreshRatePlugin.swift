import Flutter
import UIKit
import QuartzCore

public class RefreshRatePlugin: NSObject, FlutterPlugin, RefreshRateHostApi {

    private var flutterApi: RefreshRateFlutterApi?
    private var displayLink: CADisplayLink?
    private var boostDisplayLink: CADisplayLink?
    private var lastReportedRate: Double = 0
    private var powerObserver: NSObjectProtocol?
    private var thermalObserver: NSObjectProtocol?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RefreshRatePlugin()
        RefreshRateHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        instance.flutterApi = RefreshRateFlutterApi(binaryMessenger: registrar.messenger())
        instance.startMonitoring()
    }

    // MARK: - RefreshRateHostApi

    func getDisplayInfo() throws -> DisplayInfoMessage {
        let maxRate = getMaxRefreshRate()
        let currentRate = getCurrentRefreshRate()
        let proMotion = isProMotionPlistKeySet()
        let isLow = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = thermalIndex()

        return DisplayInfoMessage(
            currentRate: currentRate,
            maxRate: maxRate,
            minRate: 60.0,
            supportedRates: getSupportedRefreshRates(),
            isVariableRefreshRate: maxRate > 60,
            engineTargetRate: currentRate,
            iosProMotionEnabled: proMotion,
            androidApiLevel: nil,
            isLowPowerMode: isLow,
            thermalStateIndex: thermal,
            hasAdaptiveRefreshRate: maxRate > 60,
            displayServer: nil,
            monitorCount: nil
        )
    }

    func enable() throws { try setToMax(forceHighest: false) }
    func disable() throws { resetCap() }
    func preferMax() throws { try setToMax(forceHighest: false) }
    func preferDefault() throws { resetCap() }

    func matchContent(fps: Double) throws {
        guard #available(iOS 15.0, *) else { return }
        let maxRate = getMaxRefreshRate()
        let multiple = max(1.0, (maxRate / fps).rounded(.down))
        let preferredMax = fps * multiple
        RRSetOverrideMaxRate(Float(fps))
        RRApplyOverrideToTrackedLinks()
        setupBoostDisplayLink(min: fps, max: preferredMax, preferred: preferredMax)
    }

    func boost(durationMs: Int64) throws {
        guard #available(iOS 15.0, *) else { return }
        let maxRate = getMaxRefreshRate()
        RRSetOverrideMaxRate(0)
        RRApplyOverrideToTrackedLinks()
        setupBoostDisplayLink(min: max(maxRate * 0.66, 60.0), max: maxRate, preferred: maxRate)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(durationMs) / 1000.0) {
            self.removeBoostDisplayLink()
            RRSetOverrideMaxRate(0)
            RRApplyOverrideToTrackedLinks()
        }
    }

    func setCategory(categoryIndex: Int64) throws {
        switch categoryIndex {
        case 3: try? enable()
        case 0, 1: try? disable()
        default: break
        }
    }

    func setTouchBoost(enabled: Bool) throws {
        // No iOS equivalent; no-op
    }

    func isSupported() throws -> Bool {
        if #available(iOS 15.0, *) { return getMaxRefreshRate() > 60 }
        return false
    }

    // MARK: - Private control

    private func setToMax(forceHighest: Bool) throws {
        let maxRate = getMaxRefreshRate()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let unlocked = isProMotionPlistKeySet() || isPad
        if !unlocked { logPlistWarning(maxRate: maxRate) }
        guard #available(iOS 15.0, *) else { return }
        RRSetOverrideMaxRate(0)
        RRApplyOverrideToTrackedLinks()
        if forceHighest {
            setupBoostDisplayLink(min: max(maxRate * 0.66, 60.0), max: maxRate, preferred: maxRate)
        } else {
            removeBoostDisplayLink()
        }
    }

    private func resetCap() {
        RRSetOverrideMaxRate(60.0)
        RRApplyOverrideToTrackedLinks()
        removeBoostDisplayLink()
    }

    // MARK: - Boost display link

    @available(iOS 15.0, *)
    private func setupBoostDisplayLink(min: Double, max: Double, preferred: Double) {
        removeBoostDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(boostFired))
        RRBypassDisplayLink(link)
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(min), maximum: Float(max), preferred: Float(preferred))
        link.add(to: .main, forMode: .common)
        boostDisplayLink = link
    }

    private func removeBoostDisplayLink() {
        boostDisplayLink?.invalidate()
        boostDisplayLink = nil
    }

    @objc private func boostFired(_ link: CADisplayLink) {}

    // MARK: - Monitoring

    @objc private func monitorLinkFired(_ link: CADisplayLink) {
        let rate = link.duration > 0 ? 1.0 / link.duration : 60.0
        if abs(rate - lastReportedRate) > 5.0 {
            lastReportedRate = rate
            let info = (try? getDisplayInfo()) ?? DisplayInfoMessage(
                currentRate: rate, maxRate: rate, minRate: 60.0,
                supportedRates: [60.0, rate], isVariableRefreshRate: rate > 60,
                engineTargetRate: rate, iosProMotionEnabled: nil,
                androidApiLevel: nil, isLowPowerMode: nil,
                thermalStateIndex: nil, hasAdaptiveRefreshRate: nil,
                displayServer: nil, monitorCount: nil)
            flutterApi?.onDisplayInfoChanged(info: info) { _ in }
        }
    }

    private func startMonitoring() {
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(monitorLinkFired))
            RRBypassDisplayLink(link)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                guard let info = try? self?.getDisplayInfo() else { return }
                self?.flutterApi?.onDisplayInfoChanged(info: info) { _ in }
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let info = try? self?.getDisplayInfo() else { return }
                self?.flutterApi?.onDisplayInfoChanged(info: info) { _ in }
        }
    }

    // MARK: - Helpers

    private func getMaxRefreshRate() -> Double { Double(UIScreen.main.maximumFramesPerSecond) }

    private func getCurrentRefreshRate() -> Double {
        if let link = displayLink, link.duration > 0 { return 1.0 / link.duration }
        let max = getMaxRefreshRate()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        return (max > 60 && (isProMotionPlistKeySet() || isPad)) ? max : 60.0
    }

    private func getSupportedRefreshRates() -> [Double] {
        let max = getMaxRefreshRate()
        return max > 60 ? [60.0, max] : [60.0]
    }

    private func isProMotionPlistKeySet() -> Bool {
        return Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone") as? Bool ?? false
    }

    private func thermalIndex() -> Int64? {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return nil
        }
    }

    private func logPlistWarning(maxRate: Double) {
        print("""
        ⚠️ [refresh_rate] CADisableMinimumFrameDurationOnPhone not set in Info.plist!
        App is locked to 60Hz on this \(maxRate)Hz device.
        Add to ios/Runner/Info.plist:
          <key>CADisableMinimumFrameDurationOnPhone</key>
          <true/>
        """)
    }
}
