import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Open at the full size of the user's screen
    if let screen = NSScreen.main {
      let visibleFrame = screen.visibleFrame
      self.setFrame(visibleFrame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
