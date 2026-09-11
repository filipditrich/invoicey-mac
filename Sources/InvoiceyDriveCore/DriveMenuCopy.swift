import Foundation

public enum DriveMenuCopy: Sendable {
  public static func statusTitle(paired: Bool, lastStatusLine: String) -> String {
    if !paired {
      return DriveConstants.domainDisplayName
    }
    if lastStatusLine.isEmpty || lastStatusLine == "Connect Invoicey" {
      return DriveConstants.domainDisplayName
    }
    return lastStatusLine
  }
}
