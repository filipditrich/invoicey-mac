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
  public let itemIdentifier: NSFileProviderItemIdentifier
  public let parentItemIdentifier: NSFileProviderItemIdentifier
  public let filename: String
  public let contentType: UTType
  public let documentSize: NSNumber?
  public let isDownloaded: Bool
  public let capabilities: NSFileProviderItemCapabilities
  public let node: DriveNode

  public init(node: DriveNode) {
    self.node = node
    self.itemIdentifier = DriveItemIdentifierMap.providerID(from: node.id)
    self.parentItemIdentifier = DriveItemIdentifierMap.providerID(from: node.parent)
    self.filename = node.filename
    if node.isDirectory {
      self.contentType = .folder
      self.documentSize = nil
      self.isDownloaded = true
    } else if node.fileKind == .pdf {
      self.contentType = .pdf
      self.documentSize = nil
      self.isDownloaded = false
    } else {
      self.contentType = UTType(filenameExtension: "isdoc") ?? .xml
      self.documentSize = nil
      self.isDownloaded = false
    }
    self.capabilities = node.isDirectory
      ? [.allowsReading, .allowsContentEnumerating]
      : [.allowsReading]
    super.init()
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
        let nodes = container == .workingSet ? tree.allFiles() : tree.children(of: container)
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
        let files: [NSFileProviderItem] = tree.allFiles().map { InvoiceyDriveItem(node: $0) }
        observerBox.value.didUpdate(files)
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
