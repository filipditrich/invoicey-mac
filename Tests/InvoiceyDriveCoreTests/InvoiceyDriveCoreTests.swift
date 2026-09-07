import Foundation
import InvoiceyDriveCore
import Testing

struct PairingCallbackTests {
  @Test func readsCodeFromCustomSchemeAndAssociatedDomain() throws {
    #expect(
      try PairingCallback.authorizationCode(
        from: URL(string: "invoicey-drive://oauth?code=abc")!
      ) == "abc"
    )
    #expect(
      try PairingCallback.authorizationCode(
        from: URL(string: "https://invoicey.app/drive/oauth?code=from-aasa")!
      ) == "from-aasa"
    )
    #expect(
      try PairingCallback.authorizationCode(
        from: URL(string: "http://127.0.0.1:54321/oauth?code=loop")!
      ) == "loop"
    )
  }

  @Test func ignoresUnrelatedURLs() throws {
    #expect(
      try PairingCallback.authorizationCode(
        from: URL(string: "https://invoicey.app/drive/connect?challenge=x")!
      ) == nil
    )
  }

  @Test func surfacesProviderErrorAndMissingCode() {
    #expect(throws: DriveError.pairingFailed("access_denied")) {
      try PairingCallback.authorizationCode(
        from: URL(string: "https://invoicey.app/drive/oauth?error=access_denied")!
      )
    }
    #expect(throws: DriveError.missingAuthorizationCode) {
      try PairingCallback.authorizationCode(
        from: URL(string: "invoicey-drive://oauth")!
      )
    }
  }

  @Test func parsesLoopbackHTTPRequest() throws {
    let request = "GET /oauth?code=http-code HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
    #expect(try PairingCallback.parseHTTPRequest(request) == "http-code")
    #expect(try PairingCallback.parseHTTPRequest("GET /not-oauth HTTP/1.1\r\n") == nil)
  }
}

struct DriveConstantsTests {
  @Test func productionAPIIsCanonicalHost() {
    #expect(DriveConstants.productionAPIURL.absoluteString == "https://invoicey.app")
    #expect(DriveConstants.teamId == "72T6DX5YZU")
    #expect(DriveConstants.fileProviderBundleId == "me.ditrich.invoicey.drive.provider")
  }

  @Test func bundledRedirectUsesAssociatedDomainsOnlyOnKnownHosts() {
    let bundle = DriveConstants.bundleId
    #expect(
      DriveConstants.bundledRedirectURI(
        for: URL(string: "https://invoicey.app")!,
        bundleIdentifier: bundle
      ) == DriveConstants.associatedDomainRedirect
    )
    #expect(
      DriveConstants.bundledRedirectURI(
        for: URL(string: "https://invoicey.ditrich.me")!,
        bundleIdentifier: bundle
      )?.absoluteString == "https://invoicey.ditrich.me/drive/oauth"
    )
    #expect(
      DriveConstants.bundledRedirectURI(
        for: URL(string: "http://localhost:3000")!,
        bundleIdentifier: bundle
      ) == nil
    )
    #expect(
      DriveConstants.bundledRedirectURI(
        for: URL(string: "https://invoicey.app")!,
        bundleIdentifier: "com.example.other"
      ) == nil
    )
  }

  @Test func unsignedToolsDefaultToLocalhost() {
    #expect(
      DriveConstants.defaultAPIURLFromEnvironment(
        bundleIdentifier: "com.example.tests",
        environment: [:]
      ) == DriveConstants.defaultAPIURL
    )
    #expect(
      DriveConstants.defaultAPIURLFromEnvironment(
        bundleIdentifier: DriveConstants.bundleId,
        environment: [:]
      ) == DriveConstants.productionAPIURL
    )
  }
}

struct PKCETests {
  @Test func rfc7636S256Vector() throws {
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    let challenge = try PKCE.challenge(forVerifier: verifier)
    #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    #expect(PKCE.isValidChallenge(challenge))
  }

  @Test func generatedVerifierShape() throws {
    let pkce = try PKCE.generate()
    #expect((43...128).contains(pkce.verifier.utf8.count))
    #expect(PKCE.isValidChallenge(pkce.challenge))
    #expect(pkce.challenge == (try PKCE.challenge(forVerifier: pkce.verifier)))
    #expect(!pkce.challenge.contains("+"))
    #expect(!pkce.challenge.contains("/"))
    #expect(!pkce.challenge.contains("="))
  }

  @Test func rejectsShortVerifier() {
    #expect(throws: DriveError.self) {
      try PKCE.challenge(forVerifier: "too-short")
    }
  }
}

struct DrivePathTests {
  @Test func joinRejectsParentTraversal() {
    #expect(throws: DriveError.parentTraversal) {
      try DrivePaths.joinRelative(["2026", "..", "secret"])
    }
    #expect(throws: DriveError.parentTraversal) {
      _ = try DrivePaths.splitRelative("../etc/passwd")
    }
    #expect(throws: DriveError.parentTraversal) {
      _ = try DrivePaths.splitRelative("foo/../../x")
    }
  }

  @Test func joinRejectsAbsolute() {
    #expect(throws: DriveError.absolutePath) {
      _ = try DrivePaths.splitRelative("/etc/passwd")
    }
    #expect(throws: DriveError.absolutePath) {
      _ = try DrivePaths.splitRelative("~/Invoices")
    }
  }

  @Test func joinKeepsSafeRelative() throws {
    let path = try DrivePaths.joinRelative(["Acme", "Filip", "2026", "INV-1.pdf"])
    #expect(path == "Acme/Filip/2026/INV-1.pdf")
  }
}

struct MirrorPathTests {
  func sampleItem(
    layout: String,
    includeIsdoc: Bool = false,
    displayStatus: InvoiceDisplayStatus? = nil
  ) -> DriveIndexItem {
    DriveIndexItem(
      invoiceId: "inv-1",
      workspaceId: "ws-1",
      issuerId: "iss-1",
      workspaceName: "Acme",
      issuerName: "Filip Ditrich",
      layoutRelPath: layout,
      pdfSha256: "abc",
      isdocSha256: "def",
      hasIsdoc: includeIsdoc,
      includeIsdoc: includeIsdoc,
      issuedAt: Date(timeIntervalSince1970: 1_720_000_000),
      docType: "invoice",
      displayStatus: displayStatus
    )
  }

  @Test func indexItemMapsToMirrorPath() throws {
    let item = sampleItem(layout: "2026/faktura_12.pdf")
    let relative = try DrivePaths.relativePath(for: item, kind: .pdf)
    #expect(relative == "Acme/Filip Ditrich/2026/faktura_12.pdf")
  }

  @Test func appendsPdfWhenLayoutHasNoExtension() throws {
    let item = sampleItem(layout: "2026/INV-1")
    #expect(try DrivePaths.relativePath(for: item, kind: .pdf) == "Acme/Filip Ditrich/2026/INV-1.pdf")
  }

  @Test func isdocReplacesPdfExtension() throws {
    let item = sampleItem(layout: "2026/faktura_12.pdf", includeIsdoc: true)
    #expect(
      try DrivePaths.relativePath(for: item, kind: .isdoc)
        == "Acme/Filip Ditrich/2026/faktura_12.isdoc"
    )
  }

  @Test func sanitizesSlashInWorkspaceName() throws {
    let item = DriveIndexItem(
      invoiceId: "inv-1",
      workspaceId: "ws-1",
      issuerId: "iss-1",
      workspaceName: "Acme/Corp",
      issuerName: "Filip",
      layoutRelPath: "doc.pdf",
      pdfSha256: "",
      isdocSha256: "",
      hasIsdoc: false,
      includeIsdoc: false,
      issuedAt: Date(),
      docType: "invoice"
    )
    #expect(try DrivePaths.relativePath(for: item, kind: .pdf) == "Acme-Corp/Filip/doc.pdf")
  }

  @Test func treeBuildsYearFolderThenFile() throws {
    let item = sampleItem(layout: "2026/faktura_12.pdf")
    let tree = DriveTree(
      index: DriveIndex(generatedAt: Date(), items: [item])
    )
    let workspaces = tree.children(of: .root)
    #expect(workspaces.map(\.filename) == ["Acme"])
    let issuers = tree.children(of: .workspace("ws-1"))
    #expect(issuers.map(\.filename) == ["Filip Ditrich"])
    let underIssuer = tree.children(of: .issuer(workspaceId: "ws-1", issuerId: "iss-1"))
    #expect(underIssuer.map(\.filename) == ["2026"])
    let year = tree.children(
      of: .directory(workspaceId: "ws-1", issuerId: "iss-1", relative: "2026")
    )
    #expect(year.map(\.filename) == ["faktura_12.pdf"])
    #expect(year.first?.id == .file(invoiceId: "inv-1", kind: .pdf))
  }

  @Test func fileNodeCarriesDisplayStatus() throws {
    let item = sampleItem(layout: "2026/faktura_12.pdf", displayStatus: .overdue)
    let tree = DriveTree(index: DriveIndex(generatedAt: Date(), items: [item]))
    let year = tree.children(
      of: .directory(workspaceId: "ws-1", issuerId: "iss-1", relative: "2026")
    )
    #expect(year.first?.displayStatus == .overdue)
  }
}

struct SHASkipTests {
  @Test func skipsWhenLocalHashMatches() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("a.pdf")
    let data = Data("hello-invoicey".utf8)
    try data.write(to: file)
    let sha = SHA256File.hex(of: data)
    #expect(SHA256File.shouldSkipDownload(at: file, expectedSHA256: sha))
    #expect(SHA256File.shouldSkipDownload(at: file, expectedSHA256: sha.uppercased()))
  }

  @Test func downloadsWhenHashDiffersOrMissing() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("a.pdf")
    try Data("hello-invoicey".utf8).write(to: file)
    #expect(!SHA256File.shouldSkipDownload(at: file, expectedSHA256: "deadbeef"))
    let missing = dir.appendingPathComponent("nope.pdf")
    let sha = SHA256File.hex(of: Data("hello-invoicey".utf8))
    #expect(!SHA256File.shouldSkipDownload(at: missing, expectedSHA256: sha))
    #expect(SHA256File.shouldSkipDownload(at: file, expectedSHA256: ""))
    #expect(!SHA256File.shouldSkipDownload(at: missing, expectedSHA256: ""))
  }
}

struct FinderStatusLabelTests {
  @Test func mapsWebsiteStatusToFinderColors() {
    #expect(FinderStatusLabel.number(for: .paid) == 2)
    #expect(FinderStatusLabel.number(for: .unpaid) == 7)
    #expect(FinderStatusLabel.number(for: .future) == 7)
    #expect(FinderStatusLabel.number(for: .overdue) == 6)
    #expect(FinderStatusLabel.number(for: .draft) == 0)
    #expect(FinderStatusLabel.number(for: .cancelled) == 0)
    #expect(FinderStatusLabel.tagName(for: .paid) == "Green")
    #expect(FinderStatusLabel.tagName(for: .unpaid) == "Orange")
    #expect(FinderStatusLabel.tagName(for: .overdue) == "Red")
  }

  @Test func mergeKeepsUserTagsAndReplacesColor() {
    #expect(
      FinderStatusLabel.mergeTagNames(existing: ["Archive", "Red"], status: .paid)
        == ["Archive", "Green"]
    )
    #expect(
      FinderStatusLabel.mergeTagNames(existing: ["Červená"], status: .unpaid) == ["Orange"]
    )
    #expect(FinderStatusLabel.isFinderColorTag("Red\n6"))
  }

  @Test func applySetsLabelNumber() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("faktura.pdf")
    try Data("pdf".utf8).write(to: file)
    try FinderStatusLabel.apply(.overdue, to: file)
    let values = try file.resourceValues(forKeys: [.labelNumberKey])
    #expect(values.labelNumber == 6)
    try FinderStatusLabel.apply(nil, to: file)
    let unchanged = try file.resourceValues(forKeys: [.labelNumberKey])
    #expect(unchanged.labelNumber == 6)
    if #available(macOS 26.0, *) {
      let tagged = try file.resourceValues(forKeys: [.tagNamesKey])
      #expect(tagged.tagNames?.contains("Red") == true)
    }
  }

  @Test func tallyCountsWebsiteStatuses() {
    var result = MirrorSyncResult()
    result.tally(.overdue)
    result.tally(.unpaid)
    result.tally(.future)
    result.tally(.paid)
    result.tally(.draft)
    #expect(result.overdue == 1)
    #expect(result.unpaid == 2)
    #expect(result.paid == 1)
  }
}
