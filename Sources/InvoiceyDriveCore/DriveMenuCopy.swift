import Foundation

public enum DriveMenuCopy: Sendable {
  public static func headerTitle(version: String?) -> String {
    let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.isEmpty {
      return DriveConstants.domainDisplayName
    }
    return "\(DriveConstants.domainDisplayName)  \(trimmed)"
  }

  public static func detailStatus(paired: Bool, lastStatusLine: String) -> String? {
    guard paired else {
      return nil
    }
    let line = lastStatusLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if line.isEmpty || line == DriveConstants.domainDisplayName || line == "Connect Invoicey" {
      return nil
    }
    return line
  }

  public static func overdueTitle(_ count: Int) -> String? {
    count > 0 ? "Overdue · \(count)" : nil
  }

  public static func unpaidTitle(_ count: Int) -> String? {
    count > 0 ? "Unpaid · \(count)" : nil
  }

  public static func lastSyncTitle(iso8601: String, now: Date = Date()) -> String? {
    guard let date = parseISO8601(iso8601) else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.doesRelativeDateFormatting = true
    formatter.dateStyle = Calendar.current.isDate(date, inSameDayAs: now) ? .none : .medium
    formatter.timeStyle = .short
    return "Last sync · \(formatter.string(from: date))"
  }

  static func parseISO8601(_ raw: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: raw) {
      return date
    }
    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    return basic.date(from: raw)
  }
}
