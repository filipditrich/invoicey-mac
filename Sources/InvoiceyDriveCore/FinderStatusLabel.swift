import Foundation

/// Finder color labels from website `displayStatus`. Sets `labelNumber` only.
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
    var values = URLResourceValues()
    values.labelNumber = number(for: status)
    var mutable = url
    try mutable.setResourceValues(values)
  }
}
