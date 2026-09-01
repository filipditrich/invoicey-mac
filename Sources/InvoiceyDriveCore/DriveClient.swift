import Foundation

public struct DriveClient: Sendable {
  public var baseURL: URL
  public var token: String?

  public init(baseURL: URL, token: String? = nil) {
    self.baseURL = Self.stripTrailingSlash(baseURL)
    self.token = token
  }

  public func exchanging(code: String, verifier: String, redirectURI: URL) async throws
    -> TokenResponse
  {
    let url = try makeURL(path: "/api/drive/token")
    let body = TokenRequest(code: code, verifier: verifier, redirectUri: redirectURI.absoluteString)
    let data = try JSONEncoder().encode(body)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    let payload = try await send(request)
    do {
      return try DriveJSON.decoder().decode(TokenResponse.self, from: payload)
    } catch {
      throw DriveError.decodingFailed(error.localizedDescription)
    }
  }

  public func fetchIndex() async throws -> DriveIndex {
    let data = try await authorizedGET(path: "/api/drive/index")
    do {
      return try DriveJSON.decoder().decode(DriveIndex.self, from: data)
    } catch {
      throw DriveError.decodingFailed(error.localizedDescription)
    }
  }

  public func pdf(invoiceId: String) async throws -> Data {
    try await authorizedGET(path: "/api/drive/invoices/\(invoiceId)/pdf")
  }

  public func isdoc(invoiceId: String) async throws -> Data {
    try await authorizedGET(path: "/api/drive/invoices/\(invoiceId)/isdoc")
  }

  public func revoke() async throws {
    let url = try makeURL(path: "/api/drive/revoke")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    try applyAuthorization(&request)
    _ = try await send(request)
  }

  public func connectURL(challenge: String, redirect: URL, device: String?) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw DriveError.invalidAPIURL
    }
    components.path = "/drive/connect"
    var items = [
      URLQueryItem(name: "challenge", value: challenge),
      URLQueryItem(name: "redirect", value: redirect.absoluteString),
    ]
    if let device, !device.isEmpty {
      items.append(URLQueryItem(name: "device", value: device))
    }
    components.queryItems = items
    guard let url = components.url else {
      throw DriveError.invalidAPIURL
    }
    return url
  }

  func authorizedGET(path: String) async throws -> Data {
    let url = try makeURL(path: path)
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    try applyAuthorization(&request)
    return try await send(request)
  }

  func applyAuthorization(_ request: inout URLRequest) throws {
    guard let token, !token.isEmpty else {
      throw DriveError.notPaired
    }
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }

  func makeURL(path: String) throws -> URL {
    let root = Self.stripTrailingSlash(baseURL).absoluteString
    let suffix = path.hasPrefix("/") ? path : "/" + path
    guard let url = URL(string: root + suffix) else {
      throw DriveError.invalidAPIURL
    }
    return url
  }

  func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw DriveError.httpStatus(-1, "No HTTP response")
    }
    if http.statusCode == 401 {
      throw DriveError.unauthorized
    }
    if http.statusCode == 404 {
      if request.url?.path.hasSuffix("/isdoc") == true {
        throw DriveError.isdocUnavailable
      }
      let body = String(data: data, encoding: .utf8) ?? ""
      throw DriveError.httpStatus(404, String(body.prefix(400)))
    }
    if !(200..<300).contains(http.statusCode) {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw DriveError.httpStatus(http.statusCode, String(body.prefix(400)))
    }
    return data
  }

  static func stripTrailingSlash(_ url: URL) -> URL {
    var raw = url.absoluteString
    while raw.hasSuffix("/") {
      raw.removeLast()
    }
    return URL(string: raw) ?? url
  }
}

private struct TokenRequest: Encodable {
  var code: String
  var verifier: String
  var redirectUri: String
}
