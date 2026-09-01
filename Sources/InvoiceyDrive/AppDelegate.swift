import AppKit
import Foundation
import InvoiceyDriveCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let status = StatusItemController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    status.install()
    registerLoginItemIfBundled()
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak status] _ in
      Task { @MainActor in
        await status?.syncNow(origin: "wake")
      }
    }
    status.startPolling()
    Task { await status.syncNow(origin: "launch") }
  }

  func registerLoginItemIfBundled() {
    let bundled =
      Bundle.main.bundlePath.hasSuffix(".app")
      && Bundle.main.bundleIdentifier == DriveConstants.bundleId
    guard bundled else { return }
    do {
      try SMAppService.mainApp.register()
    } catch {
      fputs("Invoicey Drive: login item register failed: \(error.localizedDescription)\n", stderr)
    }
  }
}

@MainActor
final class StatusItemController: NSObject {
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  let tokens = TokenStore()
  var configStore: AppConfigStore?
  var pollTimer: Timer?
  var lastStatusLine = "Connect Invoicey"

  func install() {
    do {
      configStore = try AppConfigStore()
    } catch {
      lastStatusLine = error.localizedDescription
    }
    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "externaldrive",
        accessibilityDescription: "Invoicey Drive"
      )
    }
    rebuildMenu()
  }

  func startPolling() {
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: DriveConstants.pollInterval, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        await self?.syncNow(origin: "poll")
      }
    }
  }

  func rebuildMenu() {
    let menu = NSMenu()
    menu.autoenablesItems = false

    let config = (try? configStore?.load()) ?? AppConfig()
    let paired = (try? tokens.load()) != nil

    let statusLine = NSMenuItem(
      title: paired ? lastStatusLine : "Connect Invoicey",
      action: paired ? nil : #selector(connect),
      keyEquivalent: ""
    )
    statusLine.target = paired ? nil : self
    statusLine.isEnabled = true
    menu.addItem(statusLine)

    let openItem = NSMenuItem(
      title: "Open Invoicey Drive",
      action: #selector(openMirror),
      keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)

    let syncItem = NSMenuItem(title: "Sync now", action: #selector(syncClicked), keyEquivalent: "")
    syncItem.target = self
    syncItem.isEnabled = paired
    menu.addItem(syncItem)

    menu.addItem(.separator())

    let mirrorTitle: String
    if let path = config.mirrorPath, !path.isEmpty {
      mirrorTitle = "Mirror folder: \(Self.displayPath(path))"
    } else {
      mirrorTitle = "Set mirror…"
    }
    let mirrorItem = NSMenuItem(
      title: mirrorTitle,
      action: #selector(setMirror),
      keyEquivalent: ""
    )
    mirrorItem.target = self
    menu.addItem(mirrorItem)

    menu.addItem(.separator())

    if paired {
      let account = NSMenuItem(
        title: "Account · \(config.deviceId.map { String($0.prefix(8)) } ?? "signed in")",
        action: nil,
        keyEquivalent: ""
      )
      account.isEnabled = false
      menu.addItem(account)

      let signOut = NSMenuItem(title: "Sign out", action: #selector(signOutClicked), keyEquivalent: "")
      signOut.target = self
      menu.addItem(signOut)
    } else {
      let connect = NSMenuItem(
        title: "Connect Invoicey",
        action: #selector(connect),
        keyEquivalent: ""
      )
      connect.target = self
      menu.addItem(connect)
    }

    let quit = NSMenuItem(title: "Quit Invoicey Drive", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)

    statusItem.menu = menu
  }

  @objc func connect() {
    Task { await pair() }
  }

  @objc func syncClicked() {
    Task { await syncNow(origin: "menu") }
  }

  @objc func openMirror() {
    let config = (try? configStore?.load()) ?? AppConfig()
    let url = config.resolvedMirrorURL
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    NSWorkspace.shared.open(url)
  }

  @objc func setMirror() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Set mirror"
    panel.message = "Invoicey Drive writes workspace/issuer PDFs here. Drop-ins are ignored."
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        self?.saveMirror(url)
      }
    }
  }

  func saveMirror(_ url: URL) {
    do {
      let bookmark = try? MirrorBookmark.make(from: url)
      try configStore?.update { current in
        current.mirrorPath = url.path
        current.mirrorBookmark = bookmark
      }
      lastStatusLine = "Mirror folder: \(Self.displayPath(url.path))"
      rebuildMenu()
    } catch {
      present(error)
    }
  }

  @objc func signOutClicked() {
    Task { await signOut() }
  }

  @objc func quit() {
    NSApp.terminate(nil)
  }

  func pair() async {
    lastStatusLine = "Waiting for browser confirm…"
    rebuildMenu()
    do {
      let store = try store()
      let config = try store.load()
      let result = try await PairingFlow.run(apiURL: config.resolvedAPIURL)
      try PairingFlow.persist(result, tokens: tokens, config: store)
      lastStatusLine = "Connected"
      rebuildMenu()
      await syncNow(origin: "pair")
    } catch {
      lastStatusLine = "Connect Invoicey"
      rebuildMenu()
      present(error)
    }
  }

  func syncNow(origin _: String) async {
    do {
      let store = try store()
      var config = try store.load()
      guard let stored = try tokens.load() else {
        lastStatusLine = "Connect Invoicey"
        rebuildMenu()
        return
      }
      if let bookmarked = try? MirrorBookmark.resolve(config.mirrorBookmark) {
        config.mirrorPath = bookmarked.path
      }
      let root = config.resolvedMirrorURL
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let client = DriveClient(baseURL: config.resolvedAPIURL, token: stored.value)
      lastStatusLine = "Syncing…"
      rebuildMenu()
      let result = try await MirrorSynchronizer(client: client, root: root).sync()
      try store.update { current in
        current.lastSyncedAt = ISO8601DateFormatter().string(from: Date())
        current.lastError = result.failed > 0 ? "\(result.failed) file(s) failed" : nil
        if current.mirrorPath == nil {
          current.mirrorPath = root.path
        }
      }
      lastStatusLine = result.failed > 0 ? "Sync finished with errors" : "Synced just now"
      rebuildMenu()
    } catch DriveError.notPaired, DriveError.unauthorized {
      lastStatusLine = "Connect Invoicey"
      rebuildMenu()
    } catch {
      lastStatusLine = error.localizedDescription
      rebuildMenu()
    }
  }

  func signOut() async {
    do {
      let store = try store()
      let config = try store.load()
      let stored = try tokens.load()
      let client = DriveClient(baseURL: config.resolvedAPIURL, token: stored?.value)
      try await DriveSession.signOut(client: client, tokens: tokens, config: store)
      lastStatusLine = "Connect Invoicey"
      rebuildMenu()
    } catch {
      present(error)
    }
  }

  func store() throws -> AppConfigStore {
    if let configStore { return configStore }
    let created = try AppConfigStore()
    configStore = created
    return created
  }

  func present(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Invoicey Drive"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.runModal()
  }

  static func displayPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
      return "~" + path.dropFirst(home.count)
    }
    return path
  }
}
