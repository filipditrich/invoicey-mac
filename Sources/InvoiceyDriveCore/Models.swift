import Foundation

public struct DriveIndex: Codable, Sendable, Equatable {
  public var generatedAt: Date
  public var items: [DriveIndexItem]

  public init(generatedAt: Date, items: [DriveIndexItem]) {
    self.generatedAt = generatedAt
    self.items = items
  }
}

public struct DriveIndexItem: Codable, Sendable, Equatable, Identifiable {
  public var invoiceId: String
  public var workspaceId: String
  public var issuerId: String
  public var workspaceName: String
  public var issuerName: String
  public var layoutRelPath: String
  public var pdfSha256: String
  public var isdocSha256: String
  public var hasIsdoc: Bool
  public var includeIsdoc: Bool
  public var issuedAt: Date
  public var docType: String
  public var displayStatus: InvoiceDisplayStatus?

  public var id: String { invoiceId }

  public init(
    invoiceId: String,
    workspaceId: String,
    issuerId: String,
    workspaceName: String,
    issuerName: String,
    layoutRelPath: String,
    pdfSha256: String,
    isdocSha256: String,
    hasIsdoc: Bool,
    includeIsdoc: Bool,
    issuedAt: Date,
    docType: String,
    displayStatus: InvoiceDisplayStatus? = nil
  ) {
    self.invoiceId = invoiceId
    self.workspaceId = workspaceId
    self.issuerId = issuerId
    self.workspaceName = workspaceName
    self.issuerName = issuerName
    self.layoutRelPath = layoutRelPath
    self.pdfSha256 = pdfSha256
    self.isdocSha256 = isdocSha256
    self.hasIsdoc = hasIsdoc
    self.includeIsdoc = includeIsdoc
    self.issuedAt = issuedAt
    self.docType = docType
    self.displayStatus = displayStatus
  }

  public var shouldMaterializeIsdoc: Bool {
    includeIsdoc && hasIsdoc
  }
}

public struct TokenResponse: Codable, Sendable, Equatable {
  public var token: String
  public var deviceId: String

  public init(token: String, deviceId: String) {
    self.token = token
    self.deviceId = deviceId
  }
}

public enum DriveFileKind: String, Sendable, Codable, Equatable {
  case pdf
  case isdoc
}

/// Same buckets as the website (`resolveDisplayStatus`). Missing on old servers.
public enum InvoiceDisplayStatus: String, Codable, Sendable, Equatable {
  case draft
  case unpaid
  case overdue
  case paid
  case future
  case cancelled
}

public struct MirrorSyncResult: Sendable, Equatable {
  public var downloaded: Int
  public var skipped: Int
  public var failed: Int
  public var generatedAt: Date?

  public init(downloaded: Int = 0, skipped: Int = 0, failed: Int = 0, generatedAt: Date? = nil) {
    self.downloaded = downloaded
    self.skipped = skipped
    self.failed = failed
    self.generatedAt = generatedAt
  }
}

enum DriveJSON {
  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      if let date = DriveJSON.parseDate(raw) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO-8601 date: \(raw)"
      )
    }
    return decoder
  }

  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  static func parseDate(_ raw: String) -> Date? {
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
