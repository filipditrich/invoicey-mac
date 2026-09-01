import Foundation

public enum DriveConstants: Sendable {
  public static let bundleId = "me.ditrich.invoicey.drive"
  public static let domainDisplayName = "Invoicey Drive"
  public static let supportDirectoryName = "Invoicey Drive"
  public static let defaultMirrorFolderName = "Invoicey Drive"
  public static let customSchemeRedirect = "invoicey-drive://oauth"
  public static let keychainService = "me.ditrich.invoicey.drive"
  public static let keychainAccount = "device-token"
  public static let pollInterval: TimeInterval = 60
  public static let pairingTimeout: Duration = .seconds(300)

  public static let defaultAPIURL = URL(string: "http://localhost:3000")!
  public static let productionAPIURL = URL(string: "https://invoicey.ditrich.me")!

  public static func defaultAPIURLFromEnvironment() -> URL {
    if let raw = ProcessInfo.processInfo.environment["INVOICEY_DRIVE_API_URL"],
      let url = URL(string: raw),
      url.scheme != nil
    {
      return url
    }
    return defaultAPIURL
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

  public static func defaultMirrorDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(defaultMirrorFolderName, isDirectory: true)
  }
}
