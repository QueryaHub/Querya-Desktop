import Cocoa
import FlutterMacOS
import CoreVideo
import QuartzCore

public class RefreshRatePlugin: NSObject, FlutterPlugin, RefreshRateHostApi {

    private var flutterApi: RefreshRateFlutterApi?
    private var _displayLinkRef: AnyObject? // CADisplayLink on macOS 14+
    private var lastReportedRate: Double = 0
    private var displayReconfigRegistered = false

    @available(macOS 14.0, *)
    private var displayLink: CADisplayLink? {
        get { _displayLinkRef as? CADisplayLink }
        set { _displayLinkRef = newValue }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RefreshRatePlugin()
        RefreshRateHostApiSetup.setUp(binaryMessenger: registrar.messenger, api: instance)
        instance.flutterApi = RefreshRateFlutterApi(binaryMessenger: registrar.messenger)
        instance.startMonitoring()
    }

    // MARK: - RefreshRateHostApi

    func getDisplayInfo() throws -> DisplayInfoMessage {
        let current = getCurrentRate()
        let max = getMaxRate()
        let rates = getSupportedRates()
        let min = rates.min() ?? 60.0
        return DisplayInfoMessage(
            currentRate: current, maxRate: max, minRate: min,
            supportedRates: rates, isVariableRefreshRate: detectVRR(),
            engineTargetRate: 60.0,
            iosProMotionEnabled: nil, androidApiLevel: nil,
            isLowPowerMode: nil, thermalStateIndex: nil,
            hasAdaptiveRefreshRate: detectVRR(),
            displayServer: nil, monitorCount: Int64(NSScreen.screens.count))
    }

    func enable() throws {
        guard #available(macOS 14.0, *), getMaxRate() > 60 else { return }
        let max = getMaxRate()
        setupDisplayLink(minimum: 60.0, maximum: max, preferred: max)
    }

    func disable() throws {
        if #available(macOS 14.0, *) { displayLink?.invalidate(); displayLink = nil }
    }

    func preferMax() throws { try enable() }
    func preferDefault() throws { try enable() }

    func matchContent(fps: Double) throws {
        guard #available(macOS 14.0, *) else { return }
        let max = getMaxRate()
        let multiple = Swift.max(1.0, (max / fps).rounded(.down))
        setupDisplayLink(minimum: fps, maximum: fps * multiple, preferred: fps * multiple)
    }

    func boost(durationMs: Int64) throws {
        guard #available(macOS 14.0, *) else { return }
        let max = getMaxRate()
        setupDisplayLink(minimum: Swift.max(60.0, max * 0.66), maximum: max, preferred: max)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(durationMs) / 1000.0) {
            try? self.enable()
        }
    }

    func setCategory(categoryIndex: Int64) throws {
        switch categoryIndex {
        case 3: try? enable()
        case 0, 1: try? disable()
        default: break
        }
    }

    func setTouchBoost(enabled: Bool) throws {}

    func isSupported() throws -> Bool {
        if #available(macOS 14.0, *) { return getMaxRate() > 60 }
        return false
    }

    // MARK: - Private helpers

    @available(macOS 14.0, *)
    private func setupDisplayLink(minimum: Double, maximum: Double, preferred: Double) {
        displayLink?.invalidate()
        guard let screen = NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(displayLinkFired))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(minimum), maximum: Float(maximum), preferred: Float(preferred))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @available(macOS 14.0, *)
    @objc private func displayLinkFired(_ link: CADisplayLink) {
        let rate = link.duration > 0 ? round(1.0 / link.duration) : 60.0
        if abs(rate - lastReportedRate) > 5.0 {
            lastReportedRate = rate
            let info = (try? getDisplayInfo()) ?? DisplayInfoMessage(
                currentRate: rate, maxRate: rate, minRate: 60.0,
                supportedRates: [60.0, rate], isVariableRefreshRate: rate > 60,
                engineTargetRate: rate, iosProMotionEnabled: nil,
                androidApiLevel: nil, isLowPowerMode: nil,
                thermalStateIndex: nil, hasAdaptiveRefreshRate: nil,
                displayServer: nil, monitorCount: Int64(NSScreen.screens.count))
            flutterApi?.onDisplayInfoChanged(info: info) { _ in }
        }
    }

    private func startMonitoring() {
        guard !displayReconfigRegistered else { return }
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard let plugin = userInfo.flatMap({
                Unmanaged<RefreshRatePlugin>.fromOpaque($0).takeUnretainedValue() as RefreshRatePlugin?
            }) else { return }
            if flags.contains(.setModeFlag) {
                guard let info = try? plugin.getDisplayInfo() else { return }
                plugin.flutterApi?.onDisplayInfoChanged(info: info) { _ in }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        displayReconfigRegistered = true
        if #available(macOS 14.0, *), displayLink == nil {
            guard let screen = NSScreen.main else { return }
            let link = screen.displayLink(target: self, selector: #selector(displayLinkFired))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    private func getCurrentRate() -> Double {
        if #available(macOS 14.0, *), let link = displayLink, link.duration > 0 { return round(1.0 / link.duration) }
        if #available(macOS 12.0, *) { return Double(NSScreen.main?.maximumFramesPerSecond ?? 60) }
        return getRefreshRateFromCGDisplay()
    }

    private func getMaxRate() -> Double {
        if #available(macOS 12.0, *) { return Double(NSScreen.main?.maximumFramesPerSecond ?? 60) }
        return getSupportedRates().max() ?? 60.0
    }

    private func getSupportedRates() -> [Double] {
        let id = (NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        guard let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] else { return [60.0] }
        let rates = Set(modes.compactMap { $0.refreshRate > 0 ? round($0.refreshRate) : nil })
        return rates.isEmpty ? [60.0] : Array(rates).sorted()
    }

    private func detectVRR() -> Bool {
        if #available(macOS 12.0, *) {
            guard let s = NSScreen.main else { return false }
            return s.minimumRefreshInterval != s.maximumRefreshInterval
        }
        return getMaxRate() > 60
    }

    private func getRefreshRateFromCGDisplay() -> Double {
        let id = CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(id) else { return 60.0 }
        return mode.refreshRate > 0 ? mode.refreshRate : 60.0
    }
}
