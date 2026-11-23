import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // 창이 먼저 닫히면 종료 확인 창(FR-12)을 띄울 곳이 없다. 닫기를 앱 종료 요청으로 바꾼다.
  @objc func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApp.terminate(nil)
    return false
  }
}
