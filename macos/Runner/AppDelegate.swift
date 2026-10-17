import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Files Finder handed over ("Open With", double-click) before Dart asked
  /// for them, and the channel to Dart once the window has an engine (#1589).
  private var pendingPaths: [String] = []
  private var fileOpenChannel: FlutterMethodChannel?
  private var dartTookPending = false

  override init() {
    super.init()
    // macOS sends files as an Open Documents Apple Event, not in argv. The
    // handler is installed when launching starts, which replaces AppKit's
    // default one, so it does not depend on the delegate methods of
    // FlutterAppDelegate.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(installOpenDocumentsHandler(_:)),
      name: NSApplication.willFinishLaunchingNotification,
      object: nil
    )
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @objc private func installOpenDocumentsHandler(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleOpenDocuments(_:withReplyEvent:)),
      forEventClass: AEEventClass(kCoreEventClass),
      andEventID: AEEventID(kAEOpenDocuments)
    )
  }

  @objc private func handleOpenDocuments(
    _ event: NSAppleEventDescriptor,
    withReplyEvent reply: NSAppleEventDescriptor
  ) {
    guard let list = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
      return
    }
    var paths: [String] = []
    if list.numberOfItems == 0 {
      if let url = list.fileURLValue { paths.append(url.path) }
    } else {
      for index in 1...list.numberOfItems {
        if let url = list.atIndex(index)?.fileURLValue { paths.append(url.path) }
      }
    }
    deliver(paths)
  }

  private func deliver(_ paths: [String]) {
    guard !paths.isEmpty else { return }
    if dartTookPending, let channel = fileOpenChannel {
      channel.invokeMethod("openFiles", arguments: paths)
    } else {
      pendingPaths.append(contentsOf: paths)
    }
  }

  /// Called by the main window once its Flutter engine exists.
  func attachFileOpenChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "querya/file_open", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      if call.method == "takePendingFiles" {
        // From now on files go straight to Dart.
        let paths = self.pendingPaths
        self.pendingPaths.removeAll()
        self.dartTookPending = true
        result(paths)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    fileOpenChannel = channel
  }
}
