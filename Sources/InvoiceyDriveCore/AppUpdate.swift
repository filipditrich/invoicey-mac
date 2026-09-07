import Foundation

public struct DriveLatestRelease: Codable, Sendable, Equatable {
  public var version: String
  public var dmgUrl: String

  public init(version: String, dmgUrl: String) {
    self.version = version
    self.dmgUrl = dmgUrl
  }

  public var downloadURL: URL? {
    URL(string: dmgUrl)
  }

  public static func parse(_ data: Data) throws -> DriveLatestRelease {
    do {
      let release = try DriveJSON.decoder().decode(DriveLatestRelease.self, from: data)
      guard AppVersion.normalize(release.version) != nil, release.downloadURL != nil else {
        throw DriveError.decodingFailed("latest release is missing version or dmgUrl")
      }
      return release
    } catch let error as DriveError {
      throw error
    } catch {
      throw DriveError.decodingFailed(error.localizedDescription)
    }
  }
}

public enum AppVersion: Sendable {
  public static func normalize(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = trimmed.range(of: #"v?(\d+\.\d+\.\d+)"#, options: .regularExpression) else {
      return nil
    }
    var core = String(trimmed[match])
    if core.lowercased().hasPrefix("v") {
      core.removeFirst()
    }
    return core
  }

  public static func isNewer(_ latest: String, than current: String) -> Bool {
    guard let latestParts = numericParts(latest), let currentParts = numericParts(current) else {
      return false
    }
    return latestParts.lexicographicallyPrecedes(currentParts) == false
      && latestParts != currentParts
  }

  static func numericParts(_ raw: String) -> [Int]? {
    guard let normalized = normalize(raw) else {
      return nil
    }
    return normalized.split(separator: ".").compactMap { Int($0) }
  }
}

public enum UpdateCheckOutcome: Sendable, Equatable {
  case available(current: String, latest: DriveLatestRelease)
  case upToDate(current: String)
  case unknown
}

public enum AppUpdatePolicy: Sendable {
  public static let automaticInterval: TimeInterval = 86_400

  public static func outcome(
    current: String?,
    latest: DriveLatestRelease
  ) -> UpdateCheckOutcome {
    guard let current, let normalized = AppVersion.normalize(current) else {
      return .unknown
    }
    if AppVersion.isNewer(latest.version, than: normalized) {
      return .available(current: normalized, latest: latest)
    }
    return .upToDate(current: normalized)
  }

  public static func isAutomaticDue(
    lastCheckedAt: Date?,
    now: Date,
    interval: TimeInterval = automaticInterval
  ) -> Bool {
    guard let lastCheckedAt else {
      return true
    }
    return now.timeIntervalSince(lastCheckedAt) >= interval
  }
}

public struct UpdateCheckState: Codable, Sendable, Equatable {
  public var lastCheckedAt: Date?

  public init(lastCheckedAt: Date? = nil) {
    self.lastCheckedAt = lastCheckedAt
  }
}

public struct UpdateCheckStore: Sendable {
  public var url: URL

  public init(fileURL: URL) {
    self.url = fileURL
  }

  public init() throws {
    self.url = try DriveConstants.sharedSupportDirectory()
      .appendingPathComponent("update-check.json", isDirectory: false)
  }

  public func load() throws -> UpdateCheckState {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return UpdateCheckState()
    }
    let data = try Data(contentsOf: url)
    return try DriveJSON.decoder().decode(UpdateCheckState.self, from: data)
  }

  public func markChecked(at date: Date = Date()) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try DriveJSON.encoder().encode(UpdateCheckState(lastCheckedAt: date))
    try data.write(to: url, options: [.atomic])
  }
}
