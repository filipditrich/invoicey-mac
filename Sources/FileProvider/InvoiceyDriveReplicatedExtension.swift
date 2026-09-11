import FileProvider
import Foundation
import InvoiceyDriveCore
import os

/// Replicated File Provider extension. Compiles as a library; Finder sidebar requires an Xcode
/// app + appex with File Provider + App Group entitlements and a paid Developer team.
@objc(InvoiceyDriveReplicatedExtension)
public final class InvoiceyDriveReplicatedExtension: NSObject, NSFileProviderReplicatedExtension,
  @unchecked Sendable
{
  let domain: NSFileProviderDomain
  let tokens: TokenStore
  let configStore: AppConfigStore
  var tree: DriveTree
  var client: DriveClient
  let log = Logger(subsystem: DriveConstants.bundleId, category: "FileProvider")

  public required init(domain: NSFileProviderDomain) {
    self.domain = domain
    self.tokens = TokenStore.appGroup(allowDebugFileFallback: true)
    if let store = try? AppConfigStore() {
      self.configStore = store
    } else {
      self.configStore = AppConfigStore(
        fileURL: FileManager.default.temporaryDirectory
          .appendingPathComponent("invoicey-drive-config.json")
      )
    }
    let config = (try? configStore.load()) ?? AppConfig()
    let token = try? tokens.load()
    self.client = DriveClient(baseURL: config.resolvedAPIURL, token: token?.value)
    self.tree = DriveTree(
      index: DriveIndex(generatedAt: Date.distantPast, items: [])
    )
    super.init()
  }

  public func invalidate() {}

  public func item(
    for identifier: NSFileProviderItemIdentifier,
    request: NSFileProviderRequest,
    completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void
  ) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let handler = SendableBox(value: completionHandler)
    Task { [weak self] in
      guard let self else {
        handler.value(nil, NSFileProviderError(.notAuthenticated))
        return
      }
      do {
        let mapped = DriveItemIdentifierMap.driveID(from: identifier)
        if let id = mapped, id == .root || id == .workingSet, let node = self.tree.node(for: id) {
          handler.value(InvoiceyDriveItem(node: node), nil)
          progress.completedUnitCount = 1
          return
        }
        try await self.refreshTree()
        guard let id = mapped, let node = self.tree.node(for: id) else {
          throw NSFileProviderError(.noSuchItem)
        }
        handler.value(InvoiceyDriveItem(node: node), nil)
      } catch {
        handler.value(nil, error)
      }
      progress.completedUnitCount = 1
    }
    return progress
  }

  public func enumerator(
    for containerItemIdentifier: NSFileProviderItemIdentifier,
    request: NSFileProviderRequest
  ) throws -> any NSFileProviderEnumerator {
    guard let id = DriveItemIdentifierMap.driveID(from: containerItemIdentifier) else {
      throw NSFileProviderError(.noSuchItem)
    }
    return InvoiceyDriveEnumerator(container: id) { [weak self] in
      guard let self else {
        throw NSFileProviderError(.notAuthenticated)
      }
      try await self.refreshTree()
      return self.tree
    }
  }

  public func fetchContents(
    for itemIdentifier: NSFileProviderItemIdentifier,
    version requestedVersion: NSFileProviderItemVersion?,
    request: NSFileProviderRequest,
    completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void
  ) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let handler = SendableBox(value: completionHandler)
    Task { [weak self] in
      guard let self else {
        handler.value(nil, nil, NSFileProviderError(.notAuthenticated))
        return
      }
      do {
        guard let id = DriveItemIdentifierMap.driveID(from: itemIdentifier),
          case .file(let invoiceId, let kind) = id
        else {
          throw NSFileProviderError(.noSuchItem)
        }
        if self.tree.node(for: id) == nil {
          try await self.refreshTree()
        }
        guard let node = self.tree.node(for: id) else {
          throw NSFileProviderError(.noSuchItem)
        }
        let data: Data
        switch kind {
        case .pdf:
          data = try await self.client.pdf(invoiceId: invoiceId)
        case .isdoc:
          data = try await self.client.isdoc(invoiceId: invoiceId)
        }
        if data.isEmpty {
          throw DriveError.httpStatus(204, "Empty \(kind.rawValue) for \(invoiceId)")
        }
        let dest = try self.stageContents(filename: node.filename)
        try data.write(to: dest, options: [.atomic])
        handler.value(dest, InvoiceyDriveItem(node: node, downloadedSize: data.count), nil)
      } catch {
        self.log.error("fetchContents failed: \(error.localizedDescription, privacy: .public)")
        handler.value(nil, nil, error)
      }
      progress.completedUnitCount = 1
    }
    return progress
  }

  public func createItem(
    basedOn itemTemplate: NSFileProviderItem,
    fields: NSFileProviderItemFields,
    contents url: URL?,
    options: NSFileProviderCreateItemOptions = [],
    request: NSFileProviderRequest,
    completionHandler: @escaping (
      NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?
    ) -> Void
  ) -> Progress {
    _ = (fields, options, request)
    return finishCreateOrModify(
      identifier: itemTemplate.itemIdentifier,
      parent: itemTemplate.parentItemIdentifier,
      filename: itemTemplate.filename,
      contents: url,
      unknown: DriveError.dropInsIgnored,
      completionHandler: completionHandler
    )
  }

  public func modifyItem(
    _ item: NSFileProviderItem,
    baseVersion version: NSFileProviderItemVersion,
    changedFields: NSFileProviderItemFields,
    contents newContents: URL?,
    options: NSFileProviderModifyItemOptions = [],
    request: NSFileProviderRequest,
    completionHandler: @escaping (
      NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?
    ) -> Void
  ) -> Progress {
    _ = (version, changedFields, options, request)
    return finishCreateOrModify(
      identifier: item.itemIdentifier,
      parent: item.parentItemIdentifier,
      filename: item.filename,
      contents: newContents,
      unknown: DriveError.readOnlyReplica,
      completionHandler: completionHandler
    )
  }

  public func deleteItem(
    identifier: NSFileProviderItemIdentifier,
    baseVersion version: NSFileProviderItemVersion,
    options: NSFileProviderDeleteItemOptions = [],
    request: NSFileProviderRequest,
    completionHandler: @escaping ((any Error)?) -> Void
  ) -> Progress {
    _ = (identifier, version, options, request)
    /** finder delete is local only; next enumerate restores from the server index */
    completionHandler(nil)
    return Progress(totalUnitCount: 0)
  }

  func finishCreateOrModify(
    identifier: NSFileProviderItemIdentifier,
    parent: NSFileProviderItemIdentifier,
    filename: String,
    contents: URL?,
    unknown: DriveError,
    completionHandler: @escaping (
      NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?
    ) -> Void
  ) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let handler = SendableBox(value: completionHandler)
    Task { [weak self] in
      guard let self else {
        handler.value(nil, [], false, NSFileProviderError(.notAuthenticated))
        progress.completedUnitCount = 1
        return
      }
      do {
        if let node = self.resolveNode(identifier: identifier, parent: parent, filename: filename)
        {
          self.completeKnownItem(node, contents: contents, handler: handler.value)
          progress.completedUnitCount = 1
          return
        }
        try await self.refreshTree()
        if let node = self.resolveNode(identifier: identifier, parent: parent, filename: filename)
        {
          self.completeKnownItem(node, contents: contents, handler: handler.value)
        } else {
          handler.value(nil, [], false, Self.unsupported(unknown))
        }
      } catch {
        handler.value(nil, [], false, error)
      }
      progress.completedUnitCount = 1
    }
    return progress
  }

  func completeKnownItem(
    _ node: DriveNode,
    contents: URL?,
    handler: (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
  ) {
    let fetch = FileProviderHydration.shouldFetchContent(
      isDirectory: node.isDirectory,
      suppliedContentURL: contents,
      expectedSHA256: node.sha256
    )
    handler(InvoiceyDriveItem(node: node), [], fetch, nil)
  }

  func resolveNode(
    identifier: NSFileProviderItemIdentifier,
    parent: NSFileProviderItemIdentifier,
    filename: String
  ) -> DriveNode? {
    if let node = knownNode(for: identifier) {
      return node
    }
    guard let parentId = DriveItemIdentifierMap.driveID(from: parent) else {
      return nil
    }
    return tree.children(of: parentId).first { $0.filename == filename }
  }

  func knownNode(for identifier: NSFileProviderItemIdentifier) -> DriveNode? {
    guard let id = DriveItemIdentifierMap.driveID(from: identifier) else {
      return nil
    }
    return tree.node(for: id)
  }

  func stageContents(filename: String) throws -> URL {
    guard let manager = NSFileProviderManager(for: domain) else {
      throw DriveError.usage("File Provider manager unavailable.")
    }
    let dest = FileProviderHydration.stagingFileURL(
      in: try manager.temporaryDirectoryURL(),
      filename: filename
    )
    try FileManager.default.createDirectory(
      at: dest.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    return dest
  }

  func refreshTree() async throws {
    let config = try configStore.load()
    let token = try tokens.load()
    client = DriveClient(baseURL: config.resolvedAPIURL, token: token?.value)
    let index = try await client.fetchIndex()
    tree = DriveTree(index: index)
  }

  static func unsupported(_ error: DriveError) -> NSError {
    NSError(
      domain: NSCocoaErrorDomain,
      code: NSFeatureUnsupportedError,
      userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
    )
  }
}
