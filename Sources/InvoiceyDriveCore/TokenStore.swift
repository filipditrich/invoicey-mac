import Foundation
import Security

public struct StoredToken: Sendable, Equatable {
  public var value: String
  public var source: Source

  public enum Source: String, Sendable {
    case keychain
    case debugFile
  }

  public init(value: String, source: Source) {
    self.value = value
    self.source = source
  }
}

/// Device token store. Keychain first; unsigned `swift run` may fall back to a 0600 debug file.
public struct TokenStore: Sendable {
  public var accessGroup: String?
  public var allowDebugFileFallback: Bool

  public init(accessGroup: String? = nil, allowDebugFileFallback: Bool = true) {
    self.accessGroup = accessGroup
    self.allowDebugFileFallback = allowDebugFileFallback
  }

  public func load() throws -> StoredToken? {
    if let token = loadKeychain() {
      return StoredToken(value: token, source: .keychain)
    }
    if allowDebugFileFallback, let token = try loadDebugFile() {
      return StoredToken(value: token, source: .debugFile)
    }
    return nil
  }

  public func save(_ token: String) throws {
    let keychainStatus = saveKeychain(token)
    if keychainStatus == errSecSuccess {
      try deleteDebugFile()
      return
    }
    if allowDebugFileFallback {
      fputs(
        "Invoicey Drive: Keychain save failed (\(keychainStatus)); using debug-token file.\n",
        stderr
      )
      try saveDebugFile(token)
      return
    }
    throw DriveError.pairingFailed("Keychain save failed: \(keychainStatus)")
  }

  public func delete() throws {
    deleteKeychain()
    try deleteDebugFile()
  }

  func loadKeychain() -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: DriveConstants.keychainService,
      kSecAttrAccount as String: DriveConstants.keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  func saveKeychain(_ token: String) -> OSStatus {
    deleteKeychain()
    guard let data = token.data(using: .utf8) else { return errSecParam }
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: DriveConstants.keychainService,
      kSecAttrAccount as String: DriveConstants.keychainAccount,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      kSecValueData as String: data,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return SecItemAdd(query as CFDictionary, nil)
  }

  func deleteKeychain() {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: DriveConstants.keychainService,
      kSecAttrAccount as String: DriveConstants.keychainAccount,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    SecItemDelete(query as CFDictionary)
  }

  func debugFileURL() throws -> URL {
    try DriveConstants.applicationSupportDirectory()
      .appendingPathComponent("debug-token", isDirectory: false)
  }

  func loadDebugFile() throws -> String? {
    let url = try debugFileURL()
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let raw = try String(contentsOf: url, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return raw.isEmpty ? nil : raw
  }

  func saveDebugFile(_ token: String) throws {
    let url = try debugFileURL()
    try token.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }

  func deleteDebugFile() throws {
    let url = try debugFileURL()
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}
