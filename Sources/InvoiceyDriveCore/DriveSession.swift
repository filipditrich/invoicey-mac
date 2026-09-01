import Foundation

public enum DriveSession {
  public static func signOut(client: DriveClient, tokens: TokenStore, config: AppConfigStore)
    async throws
  {
    var revokeError: Error?
    if client.token != nil {
      do {
        try await client.revoke()
      } catch {
        revokeError = error
      }
    }
    try tokens.delete()
    try config.update { current in
      current.deviceId = nil
      current.lastError = revokeError.map(\.localizedDescription)
    }
    if let revokeError {
      fputs(
        "Invoicey Drive: revoke request failed (\(revokeError.localizedDescription)); local token forgotten.\n",
        stderr
      )
    }
  }

  public static func makeClient(config: AppConfig, tokens: TokenStore) throws -> DriveClient {
    let stored = try tokens.load()
    return DriveClient(baseURL: config.resolvedAPIURL, token: stored?.value)
  }
}
