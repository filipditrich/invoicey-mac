import Foundation

public enum DriveConstants: Sendable {
  public static let bundleId = "me.ditrich.invoicey.drive"
  public static let fileProviderBundleId = "me.ditrich.invoicey.drive.provider"
  public static let fileProviderDomainId = "me.ditrich.invoicey.drive"
  public static let teamId = "72T6DX5YZU"
  public static let appGroupId = "group.me.ditrich.invoicey.drive"
  /// Shared Keychain group. Developer ID profiles allow `TEAMID.*`, not the App Group id.
  public static let keychainAccessGroup = "\(teamId).\(bundleId)"
  public static let domainDisplayName = "Invoicey Drive"
  public static let supportDirectoryName = "Invoicey Drive"
  public static let defaultMirrorFolderName = "Invoicey Drive"
  public static let customSchemeRedirect = "invoicey-drive://oauth"
  public static let associatedDomainRedirect = URL(string: "https://invoicey.app/drive/oauth")!
  public static let keychainService = "me.ditrich.invoicey.drive"
  public static let keychainAccount = "device-token"
  public static let pollInterval: TimeInterval = 60
  public static let pairingTimeout: Duration = .seconds(300)

  public static let defaultAPIURL = URL(string: "http://localhost:3000")!
  public static let productionAPIURL = URL(string: "https://invoicey.app")!

  public static func defaultAPIURLFromEnvironment(
    bundleIdentifier: String? = Bundle.main.bundleIdentifier,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL {
    if let raw = environment["INVOICEY_DRIVE_API_URL"],
      let url = URL(string: raw),
      url.scheme != nil
    {
      return url
    }
    if bundleIdentifier == bundleId {
      return productionAPIURL
    }
    return defaultAPIURL
  }

  /// Associated Domains callback when the signed app talks to a known host; otherwise loopback.
  public static func bundledRedirectURI(
    for apiURL: URL,
    bundleIdentifier: String? = Bundle.main.bundleIdentifier
  ) -> URL? {
    guard bundleIdentifier == bundleId else {
      return nil
    }
    switch apiURL.host?.lowercased() {
    case "invoicey.app":
      return associatedDomainRedirect
    case "invoicey.ditrich.me":
      return URL(string: "https://invoicey.ditrich.me/drive/oauth")
    default:
      return nil
    }
  }

  public static func applicationSupportDirectory() throws -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first
    guard let base else {
      throw DriveError.configDirectoryUnavailable
    }
    let dir = base.appendingPathComponent(supportDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// App Group container when entitled (app + File Provider); otherwise Application Support.
  public static func sharedSupportDirectory() throws -> URL {
    if let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) {
      let dir = container.appendingPathComponent(supportDirectoryName, isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      return dir
    }
    return try applicationSupportDirectory()
  }

  public static func defaultMirrorDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(defaultMirrorFolderName, isDirectory: true)
  }
}
