import AppKit
import InvoiceyDriveCore

@main
enum InvoiceyDriveApp {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
