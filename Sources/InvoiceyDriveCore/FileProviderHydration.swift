import Foundation

/// When a replicated File Provider should pull remote bytes, and where to stage them.
public enum FileProviderHydration: Sendable {
  /// Dataless or 0-byte placeholders must fetch. A hash match on real bytes does not.
  public static func shouldFetchContent(
    isDirectory: Bool,
    suppliedContentURL: URL?,
    expectedSHA256: String?
  ) -> Bool {
    if isDirectory {
      return false
    }
    guard let url = suppliedContentURL else {
      return true
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      return true
    }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    if size == 0 {
      return true
    }
    guard let expectedSHA256, !expectedSHA256.isEmpty else {
      return false
    }
    return !SHA256File.shouldSkipDownload(at: url, expectedSHA256: expectedSHA256)
  }

  /// Unique folder so two PDFs never share a staging path.
  public static func stagingFileURL(
    in root: URL,
    filename: String,
    unique: String = UUID().uuidString
  ) -> URL {
    root.appendingPathComponent(unique, isDirectory: true)
      .appendingPathComponent(filename)
  }
}
