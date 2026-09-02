import Darwin
import Foundation

/// Finder color labels from website `displayStatus`.
///
/// macOS 26: set `tagNames` (the setter is 26+). 14–15: `labelNumber` plus
/// `_kMDItemUserTags` as `Orange\n7`. Do not wipe non-color user tags.
public enum FinderStatusLabel: Sendable {
  /// Classic Finder: 0 none, 2 green, 6 red, 7 orange.
  public static func number(for status: InvoiceDisplayStatus) -> Int {
    switch status {
    case .paid:
      return 2
    case .unpaid, .future:
      return 7
    case .overdue:
      return 6
    case .draft, .cancelled:
      return 0
    }
  }

  public static func tagName(for status: InvoiceDisplayStatus) -> String? {
    switch status {
    case .paid:
      return "Green"
    case .unpaid, .future:
      return "Orange"
    case .overdue:
      return "Red"
    case .draft, .cancelled:
      return nil
    }
  }

  /// English + Czech names of the seven Finder color tags.
  public static let finderColorTagNames: Set<String> = [
    "Gray", "Green", "Purple", "Blue", "Yellow", "Red", "Orange",
    "Šedá", "Zelená", "Nachová", "Fialová", "Modrá", "Žlutá", "Červená",
    "Oranžová",
  ]

  /// Keep user tags; replace any previous Finder color with this status.
  public static func mergeTagNames(
    existing: [String]?,
    status: InvoiceDisplayStatus
  ) -> [String] {
    let kept = (existing ?? []).filter { !isFinderColorTag($0) }
    guard let name = tagName(for: status) else {
      return kept
    }
    return kept + [name]
  }

  public static func isFinderColorTag(_ tag: String) -> Bool {
    let head = tag.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? tag
    return finderColorTagNames.contains(head)
  }

  public static func tagData(for status: InvoiceDisplayStatus?) -> Data? {
    guard let status, let name = tagName(for: status) else {
      return nil
    }
    return try? PropertyListSerialization.data(
      fromPropertyList: [name],
      format: .binary,
      options: 0
    )
  }

  public static func apply(_ status: InvoiceDisplayStatus?, to url: URL) throws {
    guard let status else {
      return
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      return
    }
    let merged = mergeTagNames(existing: existingTags(at: url), status: status)
    var mutable = url
    var values = URLResourceValues()
    values.labelNumber = number(for: status)
    if #available(macOS 26.0, *) {
      values.tagNames = merged
    }
    try mutable.setResourceValues(values)
    if #unavailable(macOS 26.0) {
      writeUserTags(xattrTags(merged, status: status), to: url)
    }
  }

  public static func existingTags(at url: URL) -> [String] {
    if #available(macOS 26.0, *) {
      if let names = try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames {
        return names
      }
    }
    return readUserTags(from: url)
  }

  public static func readUserTags(from url: URL) -> [String] {
    let name = "com.apple.metadata:_kMDItemUserTags"
    guard let bytes = xattrBytes(name, from: url), !bytes.isEmpty else {
      return []
    }
    guard
      let plist = try? PropertyListSerialization.propertyList(
        from: bytes,
        options: [],
        format: nil
      )
    else {
      return []
    }
    return plist as? [String] ?? []
  }

  /// Pre-26 Finder color tags in the xattr are `Name` + newline + label number.
  static func xattrTags(_ names: [String], status: InvoiceDisplayStatus) -> [String] {
    let color = tagName(for: status)
    let n = number(for: status)
    return names.map { name in
      if let color, isFinderColorTag(name) {
        return "\(color)\n\(n)"
      }
      return name
    }
  }

  static func writeUserTags(_ tags: [String], to url: URL) {
    guard
      let data = try? PropertyListSerialization.data(
        fromPropertyList: tags,
        format: .binary,
        options: 0
      )
    else {
      return
    }
    _ = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return data.withUnsafeBytes { pointer in
        setxattr(
          path,
          "com.apple.metadata:_kMDItemUserTags",
          pointer.baseAddress,
          data.count,
          0,
          0
        )
      }
    }
  }

  static func xattrBytes(_ name: String, from url: URL) -> Data? {
    url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return nil }
      let size = getxattr(path, name, nil, 0, 0, 0)
      guard size > 0 else { return nil }
      var buffer = Data(count: Int(size))
      let written = buffer.withUnsafeMutableBytes { pointer in
        getxattr(path, name, pointer.baseAddress, Int(size), 0, 0)
      }
      guard written > 0 else { return nil }
      return buffer.prefix(Int(written))
    }
  }
}
