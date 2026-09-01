import Foundation

public enum DrivePaths: Sendable {
  /// Join relative path segments. Rejects `..`, `.` (except skipped), empty, and absolute roots.
  public static func joinRelative(_ parts: [String]) throws -> String {
    var segments: [String] = []
    for part in parts {
      segments.append(contentsOf: try splitRelative(part))
    }
    if segments.isEmpty {
      throw DriveError.emptyPath
    }
    return segments.joined(separator: "/")
  }

  public static func splitRelative(_ path: String) throws -> [String] {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw DriveError.emptyPath
    }
    if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
      throw DriveError.absolutePath
    }
    if trimmed.contains("\0") {
      throw DriveError.invalidPathComponent(trimmed)
    }
    var segments: [String] = []
    for raw in trimmed.split(separator: "/", omittingEmptySubsequences: true) {
      let part = String(raw)
      if part == "." {
        continue
      }
      if part == ".." {
        throw DriveError.parentTraversal
      }
      if part.contains(":") || part.contains("\\") {
        throw DriveError.invalidPathComponent(part)
      }
      segments.append(part)
    }
    if segments.isEmpty {
      throw DriveError.emptyPath
    }
    return segments
  }

  public static func sanitizeFolderName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw DriveError.emptyPath
    }
    if trimmed == "." || trimmed == ".." {
      throw DriveError.parentTraversal
    }
    let cleaned = trimmed
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: "\\", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .replacingOccurrences(of: "\0", with: "")
    if cleaned.isEmpty {
      throw DriveError.emptyPath
    }
    if cleaned == "." || cleaned == ".." {
      throw DriveError.parentTraversal
    }
    return cleaned
  }

  public static func pdfRelativePath(for item: DriveIndexItem) throws -> String {
    try relativePath(for: item, kind: .pdf)
  }

  public static func isdocRelativePath(for item: DriveIndexItem) throws -> String {
    try relativePath(for: item, kind: .isdoc)
  }

  /// `{workspaceName}/{issuerName}/{layoutRelPath}` with the file extension for `kind`.
  public static func relativePath(for item: DriveIndexItem, kind: DriveFileKind) throws -> String {
    let workspace = try sanitizeFolderName(item.workspaceName)
    let issuer = try sanitizeFolderName(item.issuerName)
    let layout = try layoutSegments(item.layoutRelPath, kind: kind)
    return try joinRelative([workspace, issuer] + layout)
  }

  public static func layoutSegments(_ layoutRelPath: String, kind: DriveFileKind) throws -> [String]
  {
    var segments = try splitRelative(layoutRelPath)
    guard var last = segments.popLast() else {
      throw DriveError.emptyPath
    }
    last = applyExtension(last, kind: kind)
    segments.append(last)
    return segments
  }

  public static func applyExtension(_ filename: String, kind: DriveFileKind) -> String {
    switch kind {
    case .pdf:
      if filename.lowercased().hasSuffix(".pdf") {
        return filename
      }
      if filename.lowercased().hasSuffix(".isdoc") {
        return String(filename.dropLast(6)) + ".pdf"
      }
      return filename + ".pdf"
    case .isdoc:
      if filename.lowercased().hasSuffix(".isdoc") {
        return filename
      }
      if filename.lowercased().hasSuffix(".pdf") {
        return String(filename.dropLast(4)) + ".isdoc"
      }
      return filename + ".isdoc"
    }
  }

  public static func mirrorURL(root: URL, relativePath: String) throws -> URL {
    let segments = try splitRelative(relativePath)
    return segments.reduce(root) { partial, segment in
      partial.appendingPathComponent(segment, isDirectory: false)
    }
  }
}
