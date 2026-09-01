import Foundation
import InvoiceyDriveCore

@main
struct InvoiceyDriveCLI {
  static func main() async {
    let args = Array(CommandLine.arguments.dropFirst())
    do {
      try await run(args: args)
    } catch {
      fputs("invoicey-drive: \(error.localizedDescription)\n", stderr)
      Foundation.exit(1)
    }
  }

  static func run(args: [String]) async throws {
    if args.isEmpty || args.contains("-h") || args.contains("--help") {
      print(help)
      if args.isEmpty {
        Foundation.exit(1)
      }
      return
    }
    let command = args[0]
    let rest = Array(args.dropFirst())
    switch command {
    case "pair":
      try await pair(flags: rest)
    case "sync":
      try await sync(flags: rest)
    case "status":
      try status()
    case "sign-out", "signout":
      try await signOut()
    case "set-mirror":
      try setMirror(flags: rest)
    default:
      throw DriveError.usage("Unknown command: \(command). See invoicey-drive --help.")
    }
  }

  static func pair(flags: [String]) async throws {
    let parsed = FlagParser(flags)
    let configStore = try AppConfigStore()
    var config = try configStore.load()
    let apiURL = try parsed.url(named: "--api-url") ?? config.resolvedAPIURL
    let device = parsed.value(named: "--device") ?? DeviceName.current()
    print("Opening \(apiURL.absoluteString)/drive/connect …")
    print("Confirm the device in the browser. Listening on 127.0.0.1 for /oauth.")
    let result = try await PairingFlow.run(apiURL: apiURL, deviceName: device)
    try PairingFlow.persist(result, tokens: TokenStore(), config: configStore)
    config = try configStore.load()
    print("Paired. deviceId=\(result.token.deviceId)")
    print("Token stored in Keychain (or debug-token if Keychain is unavailable).")
    print("Next: invoicey-drive sync")
  }

  static func sync(flags: [String]) async throws {
    let parsed = FlagParser(flags)
    let configStore = try AppConfigStore()
    var config = try configStore.load()
    let tokens = TokenStore()
    guard let stored = try tokens.load() else {
      throw DriveError.notPaired
    }
    if let mirror = parsed.value(named: "--mirror") {
      config.mirrorPath = (mirror as NSString).expandingTildeInPath
      try configStore.save(config)
    }
    let root = config.resolvedMirrorURL
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    print("Syncing \(root.path) from \(config.resolvedAPIURL.absoluteString) …")
    let client = DriveClient(baseURL: config.resolvedAPIURL, token: stored.value)
    let result = try await MirrorSynchronizer(client: client, root: root).sync()
    try configStore.update { current in
      current.lastSyncedAt = ISO8601DateFormatter().string(from: Date())
      current.lastError = result.failed > 0 ? "\(result.failed) file(s) failed" : nil
      if current.mirrorPath == nil {
        current.mirrorPath = root.path
      }
    }
    print(
      "Done. downloaded=\(result.downloaded) skipped=\(result.skipped) failed=\(result.failed) overdue=\(result.overdue) unpaid=\(result.unpaid)"
    )
  }

  static func status() throws {
    let config = try AppConfigStore().load()
    let stored = try TokenStore().load()
    print("API:        \(config.resolvedAPIURL.absoluteString)")
    if let stored {
      print("Paired:     yes (\(stored.source.rawValue))")
    } else {
      print("Paired:     no")
    }
    print("deviceId:   \(config.deviceId ?? "—")")
    print("Mirror:     \(config.resolvedMirrorURL.path)")
    print("Last sync:  \(config.lastSyncedAt ?? "never")")
    if let lastError = config.lastError {
      print("Last error: \(lastError)")
    }
  }

  static func signOut() async throws {
    let configStore = try AppConfigStore()
    let config = try configStore.load()
    let tokens = TokenStore()
    let stored = try tokens.load()
    let client = DriveClient(baseURL: config.resolvedAPIURL, token: stored?.value)
    try await DriveSession.signOut(client: client, tokens: tokens, config: configStore)
    print("Signed out. Device token forgotten.")
  }

  static func setMirror(flags: [String]) throws {
    guard let path = flags.first, !path.hasPrefix("-") else {
      throw DriveError.usage("Usage: invoicey-drive set-mirror <path>")
    }
    let expanded = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try AppConfigStore().update { current in
      current.mirrorPath = url.path
    }
    print("Mirror folder: \(url.path)")
  }

  static let help = """
    invoicey-drive — Invoicey Drive companion (Plan 30c)

    Commands:
      pair [--api-url URL] [--device NAME]
      sync [--mirror PATH]
      status
      set-mirror PATH
      sign-out

    Pairing opens the Invoicey connect page in a browser and listens on
    http://127.0.0.1:<port>/oauth. Do not paste a PAT.

    Default API: INVOICEY_DRIVE_API_URL or http://localhost:3000
    Production:  https://invoicey.ditrich.me
    Config:      ~/Library/Application Support/Invoicey Drive/config.json
    Default mirror: ~/Invoicey Drive
    """
}

struct FlagParser {
  let args: [String]

  init(_ args: [String]) {
    self.args = args
  }

  func value(named name: String) -> String? {
    guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else {
      return nil
    }
    return args[index + 1]
  }

  func url(named name: String) throws -> URL? {
    guard let raw = value(named: name) else { return nil }
    guard let url = URL(string: raw), url.scheme != nil else {
      throw DriveError.invalidAPIURL
    }
    return url
  }
}
