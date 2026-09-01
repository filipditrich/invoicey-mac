import CryptoKit
import Foundation

public enum SHA256File: Sendable {
  public static func hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public static func hex(ofFile url: URL) throws -> String {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    return hex(of: data)
  }

  public static func matches(_ lhs: String, _ rhs: String) -> Bool {
    if lhs.isEmpty || rhs.isEmpty { return false }
    return lhs.caseInsensitiveCompare(rhs) == .orderedSame
  }

  /// Skip when the local file exists and its SHA-256 matches the index. Missing hash never skips.
  public static func shouldSkipDownload(at url: URL, expectedSHA256: String) -> Bool {
    guard !expectedSHA256.isEmpty else { return false }
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    guard let local = try? hex(ofFile: url) else { return false }
    return matches(local, expectedSHA256)
  }
}
