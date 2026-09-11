import Foundation

public struct AppConfig: Codable, Sendable, Equatable {
  public var apiUrl: String?
  public var mirrorPath: String?
  public var mirrorBookmark: String?
  public var deviceId: String?
  public var lastSyncedAt: String?
  public var lastError: String?

  public init(
    apiUrl: String? = nil,
    mirrorPath: String? = nil,
    mirrorBookmark: String? = nil,
    deviceId: String? = nil,
    lastSyncedAt: String? = nil,
    lastError: String? = nil
  ) {
    self.apiUrl = apiUrl
    self.mirrorPath = mirrorPath
    self.mirrorBookmark = mirrorBookmark
    self.deviceId = deviceId
    self.lastSyncedAt = lastSyncedAt
    self.lastError = lastError
  }

  public var resolvedAPIURL: URL {
    if let apiUrl, let url = URL(string: apiUrl), url.scheme != nil {
      return url
    }
    return DriveConstants.defaultAPIURLFromEnvironment()
  }

  public var resolvedMirrorURL: URL {
    explicitMirrorURL ?? DriveConstants.defaultMirrorDirectory()
  }

  /// True only when the user picked a folder in the menu. The old default
  /// `~/Invoicey Drive` path is not a Locations domain and is not a mirror.
  public var hasExplicitMirror: Bool {
    if let mirrorBookmark, !mirrorBookmark.isEmpty {
      return true
    }
    return false
  }

  public var explicitMirrorURL: URL? {
    guard hasExplicitMirror else {
      return nil
    }
    if let bookmarked = try? MirrorBookmark.resolve(mirrorBookmark) {
      return bookmarked
    }
    if let mirrorPath, !mirrorPath.isEmpty,
      !DriveConstants.isSandboxContainerPath(mirrorPath)
    {
      return URL(fileURLWithPath: (mirrorPath as NSString).expandingTildeInPath)
    }
    return nil
  }
}

public struct AppConfigStore: Sendable {
  public var url: URL

  public init(fileURL: URL) {
    self.url = fileURL
  }

  public init() throws {
    self.url = try DriveConstants.sharedSupportDirectory()
      .appendingPathComponent("config.json", isDirectory: false)
  }

  public func load() throws -> AppConfig {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return AppConfig()
    }
    let data = try Data(contentsOf: url)
    return try DriveJSON.decoder().decode(AppConfig.self, from: data)
  }

  public func save(_ config: AppConfig) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try DriveJSON.encoder().encode(config)
    try data.write(to: url, options: [.atomic])
  }

  public func update(_ mutate: (inout AppConfig) -> Void) throws {
    var config = try load()
    mutate(&config)
    try save(config)
  }
}

public enum MirrorBookmark: Sendable {
  public static func make(from url: URL) throws -> String {
    let data = try url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    return data.base64EncodedString()
  }

  public static func resolve(_ encoded: String?) throws -> URL? {
    guard let encoded, let data = Data(base64Encoded: encoded) else { return nil }
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    _ = url.startAccessingSecurityScopedResource()
    return url
  }
}
