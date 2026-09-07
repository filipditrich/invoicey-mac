import Foundation

/// Parses a Drive pairing callback from a custom scheme, Universal Link, or loopback URL.
public enum PairingCallback: Sendable {
  public static func authorizationCode(from url: URL) throws -> String? {
    guard isCallback(url) else {
      return nil
    }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    if let error = items?.first(where: { $0.name == "error" })?.value, !error.isEmpty {
      throw DriveError.pairingFailed(error)
    }
    guard let code = items?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
      throw DriveError.missingAuthorizationCode
    }
    return code
  }

  public static func parseHTTPRequest(_ request: String) throws -> String? {
    let firstLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init) ?? request
    let parts = firstLine.split(separator: " ")
    guard parts.count >= 2 else {
      return nil
    }
    guard let url = URL(string: "http://127.0.0.1\(parts[1])") else {
      return nil
    }
    return try authorizationCode(from: url)
  }

  public static func isCallback(_ url: URL) -> Bool {
    if url.scheme == "invoicey-drive" {
      return url.host == "oauth"
    }
    switch url.path {
    case "/oauth", "/oauth/", "/drive/oauth", "/drive/oauth/":
      return true
    default:
      return false
    }
  }
}
