import Foundation

public struct MirrorSynchronizer: Sendable {
  public var client: DriveClient
  public var root: URL

  public init(client: DriveClient, root: URL) {
    self.client = client
    self.root = root
  }

  public func sync() async throws -> MirrorSyncResult {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let index = try await client.fetchIndex()
    var result = MirrorSyncResult(generatedAt: index.generatedAt)
    for item in index.items {
      result.tally(item.displayStatus)
      do {
        let pdfDecision = try await materialize(item: item, kind: .pdf)
        accumulate(pdfDecision, into: &result)
        if item.shouldMaterializeIsdoc {
          let isdocDecision = try await materialize(item: item, kind: .isdoc)
          accumulate(isdocDecision, into: &result)
        }
      } catch {
        result.failed += 1
        fputs("Invoicey Drive: failed \(item.invoiceId): \(error.localizedDescription)\n", stderr)
      }
    }
    return result
  }

  enum Decision {
    case downloaded
    case skipped
  }

  func materialize(item: DriveIndexItem, kind: DriveFileKind) async throws -> Decision {
    let relative = try DrivePaths.relativePath(for: item, kind: kind)
    let url = try DrivePaths.mirrorURL(root: root, relativePath: relative)
    let expected = kind == .pdf ? item.pdfSha256 : item.isdocSha256
    let decision: Decision
    if SHA256File.shouldSkipDownload(at: url, expectedSHA256: expected) {
      decision = .skipped
    } else {
      let data = try await download(item: item, kind: kind)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let temp = url.appendingPathExtension("tmp")
      try data.write(to: temp, options: [.atomic])
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      try FileManager.default.moveItem(at: temp, to: url)
      decision = .downloaded
    }
    do {
      try FinderStatusLabel.apply(item.displayStatus, to: url)
    } catch {
      fputs("Invoicey Drive: label \(relative): \(error.localizedDescription)\n", stderr)
    }
    return decision
  }

  func download(item: DriveIndexItem, kind: DriveFileKind) async throws -> Data {
    switch kind {
    case .pdf:
      return try await client.pdf(invoiceId: item.invoiceId)
    case .isdoc:
      do {
        return try await client.isdoc(invoiceId: item.invoiceId)
      } catch DriveError.isdocUnavailable {
        throw DriveError.isdocUnavailable
      }
    }
  }

  func accumulate(_ decision: Decision, into result: inout MirrorSyncResult) {
    switch decision {
    case .downloaded:
      result.downloaded += 1
    case .skipped:
      result.skipped += 1
    }
  }
}
