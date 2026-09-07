import FileProvider
import Foundation
import InvoiceyDriveCore

/// Replicated File Provider extension. Compiles as a library; Finder sidebar requires an Xcode
/// app + appex with File Provider + App Group entitlements and a paid Developer team.
@objc(InvoiceyDriveReplicatedExtension)
public final class InvoiceyDriveReplicatedExtension: NSObject, NSFileProviderReplicatedExtension,
  @unchecked Sendable
{
  let tokens: TokenStore
  let configStore: AppConfigStore
  var tree: DriveTree
  var client: DriveClient

  public required init(domain: NSFileProviderDomain) {
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
    _ = domain
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
        try await self.refreshTree()
        guard let id = DriveItemIdentifierMap.driveID(from: identifier),
          let node = self.tree.node(for: id)
        else {
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
        try await self.refreshTree()
        guard let id = DriveItemIdentifierMap.driveID(from: itemIdentifier),
          case .file(let invoiceId, let kind) = id,
          let node = self.tree.node(for: id)
        else {
          throw NSFileProviderError(.noSuchItem)
        }
        let data: Data
        switch kind {
        case .pdf:
          data = try await self.client.pdf(invoiceId: invoiceId)
        case .isdoc:
          data = try await self.client.isdoc(invoiceId: invoiceId)
        }
        let temp = FileManager.default.temporaryDirectory
          .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try data.write(to: temp, options: [.atomic])
        handler.value(temp, InvoiceyDriveItem(node: node), nil)
      } catch {
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
    _ = (itemTemplate, fields, url, options, request)
    completionHandler(nil, [], false, Self.unsupported(DriveError.dropInsIgnored))
    return Progress(totalUnitCount: 0)
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
    _ = (item, version, changedFields, newContents, options, request)
    completionHandler(nil, [], false, Self.unsupported(DriveError.readOnlyReplica))
    return Progress(totalUnitCount: 0)
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
