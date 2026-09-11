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
    Task {
      await status.syncNow(origin: "launch")
      await status.syncFileProviderDomain()
      await status.checkForUpdates(force: false)
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      PairingMailbox.shared.deliver(url)
    }
  }

  func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
  ) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL
    else {
      return false
    }
    return PairingMailbox.shared.deliver(url)
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
  let tokens = TokenStore.appGroup()
  var configStore: AppConfigStore?
  var pollTimer: Timer?
  var lastStatusLine = DriveConstants.domainDisplayName
  var lastFileProviderError: String?
  var lastCounts = MirrorSyncResult()

  func install() {
    do {
      configStore = try AppConfigStore()
    } catch {
      lastStatusLine = error.localizedDescription
    }
    applyStatusAppearance()
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
      title: DriveMenuCopy.statusTitle(paired: paired, lastStatusLine: lastStatusLine),
      action: nil,
      keyEquivalent: ""
    )
    statusLine.isEnabled = false
    menu.addItem(statusLine)

    if let fileProviderError = lastFileProviderError {
      let finder = NSMenuItem(
        title: "Finder Locations: \(fileProviderError)",
        action: nil,
        keyEquivalent: ""
      )
      finder.isEnabled = false
      menu.addItem(finder)
    }

    if paired, lastCounts.overdue > 0 {
      let overdue = NSMenuItem(
        title: "Overdue · \(lastCounts.overdue)",
        action: nil,
        keyEquivalent: ""
      )
      overdue.isEnabled = false
      menu.addItem(overdue)
    }
    if paired, lastCounts.unpaid > 0 {
      let unpaid = NSMenuItem(
        title: "Unpaid · \(lastCounts.unpaid)",
        action: nil,
        keyEquivalent: ""
      )
      unpaid.isEnabled = false
      menu.addItem(unpaid)
    }

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

    menu.addItem(.separator())

    let updates = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(checkForUpdatesClicked),
      keyEquivalent: ""
    )
    updates.target = self
    menu.addItem(updates)

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
    Task { await openDrive() }
  }

  func openDrive() async {
    if let url = await FileProviderDomainRegistration.userVisibleRootURL() {
      NSWorkspace.shared.open(url)
      return
    }
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
    panel.directoryURL = DriveConstants.defaultMirrorDirectory()
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

  @objc func checkForUpdatesClicked() {
    Task { await checkForUpdates(force: true) }
  }

  @objc func quit() {
    NSApp.terminate(nil)
  }

  func checkForUpdates(force: Bool) async {
    do {
      let updateStore = try UpdateCheckStore()
      if !force {
        let last = try updateStore.load().lastCheckedAt
        guard AppUpdatePolicy.isAutomaticDue(lastCheckedAt: last, now: Date()) else {
          return
        }
      }
      let config = (try? configStore?.load()) ?? AppConfig()
      let latest = try await DriveClient(baseURL: config.resolvedAPIURL).fetchLatestRelease()
      try updateStore.markChecked()
      let current =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      presentUpdate(
        AppUpdatePolicy.outcome(current: current, latest: latest),
        interactive: force
      )
    } catch {
      if force {
        present(error)
      }
    }
  }

  func presentUpdate(_ outcome: UpdateCheckOutcome, interactive: Bool) {
    switch outcome {
    case .available(let current, let latest):
      presentAvailableUpdate(current: current, latest: latest)
    case .upToDate(let current):
      guard interactive else { return }
      presentInfo(
        title: "You’re up to date",
        message: "Invoicey Drive \(current) is the latest version."
      )
    case .unknown:
      guard interactive else { return }
      presentInfo(
        title: "Invoicey Drive",
        message: "This build has no version number. Download the latest disk image from Invoicey."
      )
    }
  }

  func presentAvailableUpdate(current: String, latest: DriveLatestRelease) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Invoicey Drive \(latest.version) is available"
    alert.informativeText =
      "You have \(current). Download the disk image and replace the app in Applications. Pairing stays."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Download")
    alert.addButton(withTitle: "Later")
    guard alert.runModal() == .alertFirstButtonReturn, let url = latest.downloadURL else {
      return
    }
    _ = NSWorkspace.shared.open(url)
  }

  func presentInfo(title: String, message: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.runModal()
  }

  func pair() async {
    lastStatusLine = "Waiting for browser confirm…"
    rebuildMenu()
    do {
      let store = try store()
      let config = try store.load()
      let result = try await PairingFlow.run(
        apiURL: config.resolvedAPIURL,
        openURL: ConnectPageOpener.open,
        redirectURI: DriveConstants.bundledRedirectURI(for: config.resolvedAPIURL)
      )
      try PairingFlow.persist(result, tokens: tokens, config: store)
      lastStatusLine = "Connected"
      rebuildMenu()
      await syncFileProviderDomain()
      await syncNow(origin: "pair")
    } catch {
      lastStatusLine = DriveConstants.domainDisplayName
      rebuildMenu()
      present(error)
    }
  }

  func syncNow(origin _: String) async {
    do {
      let store = try store()
      var config = try store.load()
      guard let stored = try tokens.load() else {
        lastCounts = MirrorSyncResult()
        lastStatusLine = DriveConstants.domainDisplayName
        applyStatusAppearance()
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
      lastCounts = result
      try? await FileProviderDomainRegistration.signalWorkingSet()
      if result.failed > 0 {
        lastStatusLine = "Sync finished with errors"
      } else if result.overdue > 0 {
        lastStatusLine = "\(result.overdue) overdue"
      } else if result.unpaid > 0 {
        lastStatusLine = "\(result.unpaid) unpaid"
      } else {
        lastStatusLine = "Synced just now"
      }
      applyStatusAppearance()
      rebuildMenu()
    } catch DriveError.notPaired, DriveError.unauthorized {
      try? DriveSession.forgetLocalSession(tokens: tokens, config: store())
      await syncFileProviderDomain()
      lastCounts = MirrorSyncResult()
      lastStatusLine = DriveConstants.domainDisplayName
      applyStatusAppearance()
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
      await syncFileProviderDomain()
      lastCounts = MirrorSyncResult()
      lastStatusLine = DriveConstants.domainDisplayName
      applyStatusAppearance()
      rebuildMenu()
    } catch {
      present(error)
    }
  }

  func syncFileProviderDomain() async {
    let paired = (try? tokens.load()) != nil
    switch await FileProviderDomainRegistration.sync(paired: paired) {
    case .failed(let message):
      lastFileProviderError = message
    case .added, .alreadyPresent:
      lastFileProviderError = nil
    case .removed, .idleUnpaired, .skippedNotBundled:
      lastFileProviderError = paired ? lastFileProviderError : nil
    }
    rebuildMenu()
  }

  func applyStatusAppearance() {
    guard let button = statusItem.button else { return }
    button.image = StatusMark.image(severity: lastCounts.menuSeverity)
    button.image?.isTemplate = lastCounts.menuSeverity == .idle
    button.toolTip = statusTooltip()
  }

  func statusTooltip() -> String {
    var parts = ["Invoicey Drive"]
    if lastCounts.overdue > 0 {
      parts.append("\(lastCounts.overdue) overdue")
    }
    if lastCounts.unpaid > 0 {
      parts.append("\(lastCounts.unpaid) unpaid")
    }
    return parts.joined(separator: " · ")
  }

  func store() throws -> AppConfigStore {
    if let configStore { return configStore }
    let created = try AppConfigStore()
    configStore = created
    return created
  }

  func present(_ error: Error) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Invoicey Drive"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.runModal()
  }

  static func displayPath(_ path: String) -> String {
    let home = DriveConstants.realHomeDirectory().path
    if path.hasPrefix(home) {
      return "~" + path.dropFirst(home.count)
    }
    return path
  }
}

/// Sandbox blocks `/usr/bin/open`; workspace is the entitled path.
enum ConnectPageOpener: Sendable {
  static func open(_ url: URL) throws {
    guard NSWorkspace.shared.open(url) else {
      throw DriveError.pairingFailed("Could not open Invoicey in the browser.")
    }
  }
}
