import Foundation

public enum DriveItemID: Hashable, Sendable, Equatable {
  case root
  case workingSet
  case workspace(String)
  case issuer(workspaceId: String, issuerId: String)
  case directory(workspaceId: String, issuerId: String, relative: String)
  case file(invoiceId: String, kind: DriveFileKind)

  public var rawValue: String {
    switch self {
    case .root:
      return "root"
    case .workingSet:
      return "workingSet"
    case .workspace(let id):
      return "w:\(id)"
    case .issuer(let workspaceId, let issuerId):
      return "i:\(workspaceId):\(issuerId)"
    case .directory(let workspaceId, let issuerId, let relative):
      return "d:\(workspaceId):\(issuerId):\(relative)"
    case .file(let invoiceId, let kind):
      return "f:\(invoiceId):\(kind.rawValue)"
    }
  }

  public static func parse(_ raw: String) -> DriveItemID? {
    if raw == "root" || raw == "" {
      return .root
    }
    if raw == "workingSet" {
      return .workingSet
    }
    if raw.hasPrefix("w:") {
      let id = String(raw.dropFirst(2))
      return id.isEmpty ? nil : .workspace(id)
    }
    if raw.hasPrefix("i:") {
      let parts = raw.dropFirst(2).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
      return .issuer(workspaceId: String(parts[0]), issuerId: String(parts[1]))
    }
    if raw.hasPrefix("d:") {
      let parts = raw.dropFirst(2).split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
      guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty, !parts[2].isEmpty else {
        return nil
      }
      return .directory(
        workspaceId: String(parts[0]),
        issuerId: String(parts[1]),
        relative: String(parts[2])
      )
    }
    if raw.hasPrefix("f:") {
      let parts = raw.dropFirst(2).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, let kind = DriveFileKind(rawValue: String(parts[1])) else {
        return nil
      }
      return .file(invoiceId: String(parts[0]), kind: kind)
    }
    return nil
  }

  public var isDirectory: Bool {
    switch self {
    case .file:
      return false
    case .root, .workingSet, .workspace, .issuer, .directory:
      return true
    }
  }
}

public struct DriveNode: Equatable, Sendable {
  public var id: DriveItemID
  public var parent: DriveItemID
  public var filename: String
  public var isDirectory: Bool
  public var invoiceId: String?
  public var fileKind: DriveFileKind?
  public var sha256: String?
  public var displayStatus: InvoiceDisplayStatus?
  public var contentTypeIdentifier: String

  public init(
    id: DriveItemID,
    parent: DriveItemID,
    filename: String,
    isDirectory: Bool,
    invoiceId: String? = nil,
    fileKind: DriveFileKind? = nil,
    sha256: String? = nil,
    displayStatus: InvoiceDisplayStatus? = nil,
    contentTypeIdentifier: String
  ) {
    self.id = id
    self.parent = parent
    self.filename = filename
    self.isDirectory = isDirectory
    self.invoiceId = invoiceId
    self.fileKind = fileKind
    self.sha256 = sha256
    self.displayStatus = displayStatus
    self.contentTypeIdentifier = contentTypeIdentifier
  }
}

/// Server index mapped to the Finder tree. Layout comes from the index; the Mac does not invent folders.
public struct DriveTree: Sendable, Equatable {
  public var generatedAt: Date
  public var items: [DriveIndexItem]

  public init(index: DriveIndex) {
    self.generatedAt = index.generatedAt
    self.items = index.items
  }

  public func item(invoiceId: String) -> DriveIndexItem? {
    items.first(where: { $0.invoiceId == invoiceId })
  }

  public func node(for id: DriveItemID) -> DriveNode? {
    switch id {
    case .root:
      return DriveNode(
        id: .root,
        parent: .root,
        filename: DriveConstants.domainDisplayName,
        isDirectory: true,
        contentTypeIdentifier: "public.folder"
      )
    case .workingSet:
      return DriveNode(
        id: .workingSet,
        parent: .root,
        filename: "workingSet",
        isDirectory: true,
        contentTypeIdentifier: "public.folder"
      )
    case .workspace(let workspaceId):
      guard let item = items.first(where: { $0.workspaceId == workspaceId }),
        let name = try? DrivePaths.sanitizeFolderName(item.workspaceName)
      else { return nil }
      return DriveNode(
        id: id,
        parent: .root,
        filename: name,
        isDirectory: true,
        contentTypeIdentifier: "public.folder"
      )
    case .issuer(let workspaceId, let issuerId):
      guard let item = items.first(where: { $0.workspaceId == workspaceId && $0.issuerId == issuerId }),
        let name = try? DrivePaths.sanitizeFolderName(item.issuerName)
      else { return nil }
      return DriveNode(
        id: id,
        parent: .workspace(workspaceId),
        filename: name,
        isDirectory: true,
        contentTypeIdentifier: "public.folder"
      )
    case .directory(let workspaceId, let issuerId, let relative):
      guard let filename = relative.split(separator: "/").last.map(String.init) else { return nil }
      let parent: DriveItemID
      if let slash = relative.lastIndex(of: "/") {
        let parentRel = String(relative[..<slash])
        parent = .directory(workspaceId: workspaceId, issuerId: issuerId, relative: parentRel)
      } else {
        parent = .issuer(workspaceId: workspaceId, issuerId: issuerId)
      }
      return DriveNode(
        id: id,
        parent: parent,
        filename: filename,
        isDirectory: true,
        contentTypeIdentifier: "public.folder"
      )
    case .file(let invoiceId, let kind):
      guard let item = item(invoiceId: invoiceId),
        let segments = try? DrivePaths.layoutSegments(item.layoutRelPath, kind: kind),
        let filename = segments.last
      else { return nil }
      if kind == .isdoc && !item.shouldMaterializeIsdoc {
        return nil
      }
      return DriveNode(
        id: id,
        parent: parentOfFile(item: item, segments: segments),
        filename: filename,
        isDirectory: false,
        invoiceId: invoiceId,
        fileKind: kind,
        sha256: kind == .pdf ? item.pdfSha256 : item.isdocSha256,
        displayStatus: item.displayStatus,
        contentTypeIdentifier: kind == .pdf ? "com.adobe.pdf" : "public.xml"
      )
    }
  }

  public func children(of parent: DriveItemID) -> [DriveNode] {
    switch parent {
    case .root:
      return uniqueWorkspaces()
    case .workingSet:
      return allFiles()
    case .workspace(let workspaceId):
      return uniqueIssuers(in: workspaceId)
    case .issuer(let workspaceId, let issuerId):
      return children(workspaceId: workspaceId, issuerId: issuerId, prefix: [])
    case .directory(let workspaceId, let issuerId, let relative):
      let prefix = relative.split(separator: "/").map(String.init)
      return children(workspaceId: workspaceId, issuerId: issuerId, prefix: prefix)
    case .file:
      return []
    }
  }

  public func allFiles() -> [DriveNode] {
    items.flatMap { item -> [DriveNode] in
      var nodes: [DriveNode] = []
      if let pdf = node(for: .file(invoiceId: item.invoiceId, kind: .pdf)) {
        nodes.append(pdf)
      }
      if item.shouldMaterializeIsdoc,
        let isdoc = node(for: .file(invoiceId: item.invoiceId, kind: .isdoc))
      {
        nodes.append(isdoc)
      }
      return nodes
    }
  }

  func uniqueWorkspaces() -> [DriveNode] {
    var seen = Set<String>()
    var nodes: [DriveNode] = []
    for item in items {
      if seen.insert(item.workspaceId).inserted,
        let node = node(for: .workspace(item.workspaceId))
      {
        nodes.append(node)
      }
    }
    return nodes
  }

  func uniqueIssuers(in workspaceId: String) -> [DriveNode] {
    var seen = Set<String>()
    var nodes: [DriveNode] = []
    for item in items where item.workspaceId == workspaceId {
      if seen.insert(item.issuerId).inserted,
        let node = node(for: .issuer(workspaceId: workspaceId, issuerId: item.issuerId))
      {
        nodes.append(node)
      }
    }
    return nodes
  }

  func children(workspaceId: String, issuerId: String, prefix: [String]) -> [DriveNode] {
    var directories = Set<String>()
    var files: [DriveNode] = []
    for item in items where item.workspaceId == workspaceId && item.issuerId == issuerId {
      appendChildren(
        item: item,
        kind: .pdf,
        prefix: prefix,
        directories: &directories,
        files: &files
      )
      if item.shouldMaterializeIsdoc {
        appendChildren(
          item: item,
          kind: .isdoc,
          prefix: prefix,
          directories: &directories,
          files: &files
        )
      }
    }
    let dirNodes: [DriveNode] = directories.compactMap { name in
      let relative = (prefix + [name]).joined(separator: "/")
      return node(
        for: .directory(workspaceId: workspaceId, issuerId: issuerId, relative: relative)
      )
    }
    .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    let fileNodes = files.sorted {
      $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
    }
    return dirNodes + fileNodes
  }

  func appendChildren(
    item: DriveIndexItem,
    kind: DriveFileKind,
    prefix: [String],
    directories: inout Set<String>,
    files: inout [DriveNode]
  ) {
    guard let segments = try? DrivePaths.layoutSegments(item.layoutRelPath, kind: kind) else {
      return
    }
    guard segments.starts(with: prefix), segments.count > prefix.count else { return }
    let rest = Array(segments.dropFirst(prefix.count))
    if rest.count == 1 {
      if let node = node(for: .file(invoiceId: item.invoiceId, kind: kind)) {
        files.append(node)
      }
    } else if let next = rest.first {
      directories.insert(next)
    }
  }

  func parentOfFile(item: DriveIndexItem, segments: [String]) -> DriveItemID {
    if segments.count <= 1 {
      return .issuer(workspaceId: item.workspaceId, issuerId: item.issuerId)
    }
    let relative = segments.dropLast().joined(separator: "/")
    return .directory(
      workspaceId: item.workspaceId,
      issuerId: item.issuerId,
      relative: relative
    )
  }
}
