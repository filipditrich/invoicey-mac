import CryptoKit
import Foundation

public struct PKCE: Sendable, Equatable {
  public var verifier: String
  public var challenge: String

  public init(verifier: String, challenge: String) {
    self.verifier = verifier
    self.challenge = challenge
  }

  public static let unreservedCharset = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  )

  /// RFC 7636 S256: BASE64URL(SHA256(ASCII(verifier))).
  public static func challenge(forVerifier verifier: String) throws -> String {
    try validateVerifier(verifier)
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return base64URL(Data(digest))
  }

  public static func generate() throws -> PKCE {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw DriveError.pairingFailed("Could not generate a PKCE verifier.")
    }
    let verifier = base64URL(Data(bytes))
    let challenge = try challenge(forVerifier: verifier)
    return PKCE(verifier: verifier, challenge: challenge)
  }

  public static func validateVerifier(_ verifier: String) throws {
    let count = verifier.utf8.count
    guard (43...128).contains(count) else {
      throw DriveError.pairingFailed("PKCE verifier must be 43-128 characters.")
    }
    if verifier.unicodeScalars.contains(where: { !unreservedCharset.contains($0) }) {
      throw DriveError.pairingFailed("PKCE verifier must use unreserved characters.")
    }
  }

  public static func isValidChallenge(_ challenge: String) -> Bool {
    let count = challenge.utf8.count
    guard (43...128).contains(count) else { return false }
    if challenge.contains("=") || challenge.contains("+") || challenge.contains("/") {
      return false
    }
    return !challenge.unicodeScalars.contains(where: { !unreservedCharset.contains($0) })
  }

  public static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
