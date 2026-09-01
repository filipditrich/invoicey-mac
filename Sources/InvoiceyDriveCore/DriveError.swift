import Foundation

public enum DriveError: Error, LocalizedError, Sendable, Equatable {
  case configDirectoryUnavailable
  case invalidAPIURL
  case invalidRedirectURL
  case pairingTimeout
  case pairingFailed(String)
  case missingAuthorizationCode
  case notPaired
  case unauthorized
  case httpStatus(Int, String)
  case decodingFailed(String)
  case isdocUnavailable
  case parentTraversal
  case absolutePath
  case emptyPath
  case invalidPathComponent(String)
  case dropInsIgnored
  case readOnlyReplica
  case usage(String)

  public var errorDescription: String? {
    switch self {
    case .configDirectoryUnavailable:
      return "Could not create Application Support/Invoicey Drive."
    case .invalidAPIURL:
      return "INVOICEY_DRIVE_API_URL is not a valid URL."
    case .invalidRedirectURL:
      return "Could not build the OAuth redirect URL."
    case .pairingTimeout:
      return "Pairing timed out. Confirm the device on the web page and try again."
    case .pairingFailed(let message):
      return message
    case .missingAuthorizationCode:
      return "The redirect did not include an authorization code."
    case .notPaired:
      return "Not paired. Run invoicey-drive pair."
    case .unauthorized:
      return "Device token rejected. Pair again."
    case .httpStatus(let code, let body):
      return "HTTP \(code): \(body)"
    case .decodingFailed(let message):
      return "Could not decode Drive response: \(message)"
    case .isdocUnavailable:
      return "ISDOC is not available for this invoice."
    case .parentTraversal:
      return "layoutRelPath must not contain parent segments."
    case .absolutePath:
      return "layoutRelPath must be a relative path."
    case .emptyPath:
      return "Path is empty after sanitizing."
    case .invalidPathComponent(let name):
      return "Invalid path component: \(name)"
    case .dropInsIgnored:
      return "Invoicey Drive ignores files dropped in from Finder."
    case .readOnlyReplica:
      return "Invoicey Drive is a read-only replica. Cancel invoices on the web."
    case .usage(let message):
      return message
    }
  }
}
