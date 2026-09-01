import Foundation
import Network
import SystemConfiguration

public enum DeviceName {
  public static func current() -> String {
    if let cfName = SCDynamicStoreCopyComputerName(nil, nil) {
      let name = cfName as String
      if !name.isEmpty {
        return name
      }
    }
    return "Mac"
  }
}

public enum Browser {
  public static func open(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    try process.run()
  }
}

public struct PairingResult: Sendable, Equatable {
  public var token: TokenResponse
  public var redirectURI: URL
  public var apiURL: URL

  public init(token: TokenResponse, redirectURI: URL, apiURL: URL) {
    self.token = token
    self.redirectURI = redirectURI
    self.apiURL = apiURL
  }
}

public enum PairingFlow {
  /// PKCE pair: local HTTP callback on 127.0.0.1, then POST /api/drive/token.
  public static func run(
    apiURL: URL,
    deviceName: String = DeviceName.current(),
    timeout: Duration = DriveConstants.pairingTimeout,
    openURL: (@Sendable (URL) throws -> Void)? = nil
  ) async throws -> PairingResult {
    let pkce = try PKCE.generate()
    let server = OAuthCallbackServer()
    let redirect = try await server.start()
    defer { server.stop() }

    let client = DriveClient(baseURL: apiURL)
    let connect = try client.connectURL(
      challenge: pkce.challenge,
      redirect: redirect,
      device: deviceName
    )
    if let openURL {
      try openURL(connect)
    } else {
      try Browser.open(connect)
    }

    let code: String
    do {
      code = try await server.waitForCode(timeout: timeout)
    } catch is CancellationError {
      throw DriveError.pairingTimeout
    }

    let token = try await client.exchanging(
      code: code,
      verifier: pkce.verifier,
      redirectURI: redirect
    )
    return PairingResult(token: token, redirectURI: redirect, apiURL: apiURL)
  }

  public static func persist(_ result: PairingResult, tokens: TokenStore, config: AppConfigStore)
    throws
  {
    try tokens.save(result.token.token)
    try config.update { current in
      current.apiUrl = result.apiURL.absoluteString
      current.deviceId = result.token.deviceId
      current.lastError = nil
    }
  }
}

final class OAuthCallbackServer: @unchecked Sendable {
  private let queue = DispatchQueue(label: "me.ditrich.invoicey.drive.oauth")
  private var listener: NWListener?
  private var connections: [NWConnection] = []
  private var continuation: CheckedContinuation<String, Error>?
  private var startContinuation: CheckedContinuation<URL, Error>?
  private var pendingCode: String?
  private var pendingError: Error?
  private var finished = false
  private var announcedPort = false

  func start() async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        self.startContinuation = continuation
        do {
          let params = NWParameters.tcp
          params.allowLocalEndpointReuse = true
          params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
          )
          let listener = try NWListener(using: params, on: .any)
          self.listener = listener
          listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
          }
          listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
              guard !self.announcedPort else { return }
              self.announcedPort = true
              guard let port = listener.port,
                let url = URL(string: "http://127.0.0.1:\(port.rawValue)/oauth")
              else {
                self.resumeStart(throwing: DriveError.invalidRedirectURL)
                return
              }
              self.resumeStart(returning: url)
            case .failed(let error):
              self.resumeStart(throwing: error)
            default:
              break
            }
          }
          listener.start(queue: self.queue)
        } catch {
          self.resumeStart(throwing: error)
        }
      }
    }
  }

  func waitForCode(timeout: Duration) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask {
        try await withCheckedThrowingContinuation { continuation in
          self.queue.async {
            if let code = self.pendingCode {
              self.pendingCode = nil
              continuation.resume(returning: code)
              return
            }
            if let error = self.pendingError {
              self.pendingError = nil
              continuation.resume(throwing: error)
              return
            }
            if self.finished {
              continuation.resume(throwing: DriveError.pairingFailed("Callback already finished."))
              return
            }
            self.continuation = continuation
          }
        }
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw DriveError.pairingTimeout
      }
      guard let code = try await group.next() else {
        throw DriveError.pairingTimeout
      }
      group.cancelAll()
      return code
    }
  }

  func stop() {
    queue.async {
      self.finished = true
      self.listener?.cancel()
      self.listener = nil
      for connection in self.connections {
        connection.cancel()
      }
      self.connections.removeAll()
      if let continuation = self.continuation {
        self.continuation = nil
        continuation.resume(throwing: DriveError.pairingTimeout)
      }
    }
  }

  func handle(_ connection: NWConnection) {
    connections.append(connection)
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] content, _, _, error in
      guard let self else { return }
      if error != nil {
        connection.cancel()
        return
      }
      guard let content, let request = String(data: content, encoding: .utf8) else {
        connection.cancel()
        return
      }
      do {
        guard let code = try Self.parseCode(from: request) else {
          self.respond(connection, status: 404, body: Self.html("Not found."))
          return
        }
        self.respond(
          connection,
          status: 200,
          body: Self.html("This Mac is connected to Invoicey. You can close this tab.")
        )
        self.succeed(code)
      } catch {
        self.respond(connection, status: 400, body: Self.html(error.localizedDescription))
        self.fail(error)
      }
    }
  }

  func succeed(_ code: String) {
    if let continuation {
      finished = true
      self.continuation = nil
      continuation.resume(returning: code)
    } else {
      pendingCode = code
      finished = true
    }
  }

  func fail(_ error: Error) {
    if finished { return }
    finished = true
    if let continuation {
      self.continuation = nil
      continuation.resume(throwing: error)
    } else {
      pendingError = error
    }
  }

  func resumeStart(returning url: URL) {
    startContinuation?.resume(returning: url)
    startContinuation = nil
  }

  func resumeStart(throwing error: Error) {
    startContinuation?.resume(throwing: error)
    startContinuation = nil
  }

  func respond(_ connection: NWConnection, status: Int, body: String) {
    let payload = Data(body.utf8)
    let header = """
      HTTP/1.1 \(status) \(status == 200 ? "OK" : "Bad Request")\r
      Content-Type: text/html; charset=utf-8\r
      Content-Length: \(payload.count)\r
      Connection: close\r
      \r

      """
    var data = Data(header.utf8)
    data.append(payload)
    connection.send(
      content: data,
      completion: .contentProcessed { _ in
        connection.cancel()
      }
    )
  }

  static func parseCode(from request: String) throws -> String? {
    let firstLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init) ?? request
    let parts = firstLine.split(separator: " ")
    guard parts.count >= 2 else {
      return nil
    }
    guard let url = URL(string: "http://127.0.0.1\(parts[1])") else {
      return nil
    }
    let path = url.path
    if path != "/oauth" && path != "/oauth/" {
      return nil
    }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
      throw DriveError.pairingFailed(error)
    }
    guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value,
      !code.isEmpty
    else {
      throw DriveError.missingAuthorizationCode
    }
    return code
  }

  static func html(_ message: String) -> String {
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Invoicey Drive</title>
      <style>
        body { font: 15px/1.45 -apple-system, BlinkMacSystemFont, sans-serif; margin: 48px; color: #1c1c1c; }
      </style>
    </head>
    <body>
      <p>\(message)</p>
    </body>
    </html>
    """
  }
}
