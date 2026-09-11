import FileProvider
import Foundation
import InvoiceyDriveCore
import UniformTypeIdentifiers

struct SendableBox<T>: @unchecked Sendable {
  let value: T
}

public enum DriveItemIdentifierMap {
  public static func driveID(from identifier: NSFileProviderItemIdentifier) -> DriveItemID? {
    if identifier == .rootContainer {
      return .root
    }
    if identifier == .workingSet {
      return .workingSet
    }
    if identifier == .trashContainer {
      return nil
    }
    return DriveItemID.parse(identifier.rawValue)
  }

  public static func providerID(from id: DriveItemID) -> NSFileProviderItemIdentifier {
    switch id {
    case .root:
      return .rootContainer
    case .workingSet:
      return .workingSet
    default:
      return NSFileProviderItemIdentifier(id.rawValue)
    }
  }
}

public final class InvoiceyDriveItem: NSObject, NSFileProviderItem {
  @objc public let itemIdentifier: NSFileProviderItemIdentifier
  @objc public let parentItemIdentifier: NSFileProviderItemIdentifier
  @objc public let filename: String
  @objc public let contentType: UTType
  @objc public let documentSize: NSNumber?
  @objc public let isDownloaded: Bool
  @objc public let capabilities: NSFileProviderItemCapabilities
  @objc public let contentModificationDate: Date?
  @objc public let creationDate: Date?
  public let node: DriveNode

  public init(node: DriveNode, downloadedSize: Int? = nil) {
    self.node = node
    self.itemIdentifier = DriveItemIdentifierMap.providerID(from: node.id)
    self.parentItemIdentifier = DriveItemIdentifierMap.providerID(from: node.parent)
    self.filename = node.filename
    self.contentModificationDate = node.issuedAt
    self.creationDate = node.issuedAt
    if node.isDirectory {
      self.contentType = .folder
      self.documentSize = nil
      self.isDownloaded = true
    } else if node.fileKind == .pdf {
      self.contentType = .pdf
      self.documentSize = downloadedSize.map { NSNumber(value: $0) }
      self.isDownloaded = downloadedSize != nil
    } else {
      self.contentType = UTType(filenameExtension: "isdoc") ?? .xml
      self.documentSize = downloadedSize.map { NSNumber(value: $0) }
      self.isDownloaded = downloadedSize != nil
    }
    self.capabilities = node.isDirectory
      ? [.allowsReading, .allowsContentEnumerating]
      : [.allowsReading]
    super.init()
  }

  @objc public var isUploaded: Bool { true }

  @objc public var isMostRecentVersionDownloaded: Bool { isDownloaded }

  @objc public var itemVersion: NSFileProviderItemVersion {
    Self.version(for: node, downloadedSize: documentSize?.intValue)
  }

  @objc public var tagData: Data? {
    FinderStatusLabel.tagData(for: node.displayStatus)
  }

  public static func version(for node: DriveNode, downloadedSize: Int? = nil) -> NSFileProviderItemVersion {
    /** epoch invalidates 0-byte snapshots created before shouldFetchContent */
    let epoch = "2"
    let hash = node.sha256.flatMap { $0.isEmpty ? nil : $0 } ?? "dir:\(node.id.rawValue)"
    let contentSeed = "\(hash)|\(epoch)"
    let metadataSeed = "\(node.id.rawValue)|\(node.filename)|\(downloadedSize ?? 0)|\(epoch)"
    return NSFileProviderItemVersion(
      contentVersion: Data(contentSeed.utf8),
      metadataVersion: Data(metadataSeed.utf8)
    )
  }
}

public final class InvoiceyDriveEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable
{
  public let container: DriveItemID
  let loadTree: () async throws -> DriveTree

  public init(tree: DriveTree, container: DriveItemID) {
    self.container = container
    self.loadTree = { tree }
  }

  public init(
    container: DriveItemID,
    loadTree: @escaping () async throws -> DriveTree
  ) {
    self.container = container
    self.loadTree = loadTree
  }

  public func invalidate() {}

  public func enumerateItems(
    for observer: NSFileProviderEnumerationObserver,
    startingAt page: NSFileProviderPage
  ) {
    let load = SendableBox(value: loadTree)
    let container = self.container
    let observerBox = SendableBox(value: observer)
    Task {
      do {
        let tree = try await load.value()
        let nodes = container == .workingSet ? tree.allNodes() : tree.children(of: container)
        let items: [NSFileProviderItem] = nodes.map { InvoiceyDriveItem(node: $0) }
        observerBox.value.didEnumerate(items)
        observerBox.value.finishEnumerating(upTo: nil)
      } catch {
        observerBox.value.finishEnumeratingWithError(error)
      }
    }
  }

  public func enumerateChanges(
    for observer: NSFileProviderChangeObserver,
    from syncAnchor: NSFileProviderSyncAnchor
  ) {
    let load = SendableBox(value: loadTree)
    let observerBox = SendableBox(value: observer)
    Task {
      do {
        let tree = try await load.value()
        let stamp = ISO8601DateFormatter().string(from: tree.generatedAt)
        let items: [NSFileProviderItem] = tree.allNodes().map { InvoiceyDriveItem(node: $0) }
        observerBox.value.didUpdate(items)
        observerBox.value.finishEnumeratingChanges(
          upTo: NSFileProviderSyncAnchor(Data(stamp.utf8)),
          moreComing: false
        )
      } catch {
        observerBox.value.finishEnumeratingWithError(error)
      }
    }
  }

  public func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
    let load = SendableBox(value: loadTree)
    let handler = SendableBox(value: completionHandler)
    Task {
      let tree = try? await load.value()
      let date = tree?.generatedAt ?? Date.distantPast
      let stamp = ISO8601DateFormatter().string(from: date)
      handler.value(NSFileProviderSyncAnchor(Data(stamp.utf8)))
    }
  }
}
