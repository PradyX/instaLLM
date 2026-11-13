import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    let storageChannel = FlutterMethodChannel(name: "installm/storage_info", binaryMessenger: flutterViewController.engine.binaryMessenger)
    storageChannel.setMethodCallHandler { (call, result) in
      if call.method == "getStorageInfo" {
        do {
          let fileURL = URL(fileURLWithPath: NSHomeDirectory())
          let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey])
          
          let free = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
          let total = values.volumeTotalCapacity ?? 0
          
          result([
            "freeBytes": free,
            "totalBytes": total
          ])
        } catch {
          result(FlutterError(code: "UNAVAILABLE", message: "Could not get storage info", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let accessibilityChannel = FlutterMethodChannel(
      name: "installm/accessibility",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    accessibilityChannel.setMethodCallHandler { call, result in
      if call.method == "shouldReduceMotion" {
        result(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      accessibilityChannel.invokeMethod(
        "reduceMotionChanged",
        arguments: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      )
    }

    let runtimePathsChannel = FlutterMethodChannel(
      name: "installm/runtime_paths",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    runtimePathsChannel.setMethodCallHandler { call, result in
      if call.method == "getAppleFrameworksDir" {
        result(Bundle.main.privateFrameworksPath)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
    configureWindowFrame()
  }

  /// Small enough for a laptop screen, tall enough that the Companion's orb,
  /// the pill and a usable session fit without clipping.
  private static let minimumContentSize = NSSize(width: 700, height: 560)

  private func configureWindowFrame() {
    contentMinSize = Self.minimumContentSize
    let autosaveName = NSWindow.FrameAutosaveName("InstaLLMMainWindow.v1")
    let restored = setFrameUsingName(autosaveName)

    if !restored {
      // Start wide enough for the desktop sidebar and a comfortable chat area.
      setContentSize(NSSize(width: 1200, height: 800))
      center()
    }

    // A saved frame can belong to a larger or disconnected display. Keep the
    // whole window visible while retaining user-selected sizes and positions.
    if let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame {
      var fittedFrame = frame
      fittedFrame.size.width = max(
        min(fittedFrame.width, visibleFrame.width),
        Self.minimumContentSize.width
      )
      fittedFrame.size.height = max(
        min(fittedFrame.height, visibleFrame.height),
        Self.minimumContentSize.height
      )
      fittedFrame.origin.x = min(max(fittedFrame.minX, visibleFrame.minX),
                                visibleFrame.maxX - fittedFrame.width)
      fittedFrame.origin.y = min(max(fittedFrame.minY, visibleFrame.minY),
                                visibleFrame.maxY - fittedFrame.height)
      setFrame(fittedFrame, display: true)
    }

    setFrameAutosaveName(autosaveName)
  }
}
