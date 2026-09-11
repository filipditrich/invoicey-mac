import Foundation
import InvoiceyDriveCore
import Testing

struct FileProviderHydrationTests {
  @Test func foldersNeverFetchContent() {
    #expect(
      !FileProviderHydration.shouldFetchContent(
        isDirectory: true,
        suppliedContentURL: nil,
        expectedSHA256: nil
      )
    )
  }

  @Test func datalessFilesMustFetch() {
    #expect(
      FileProviderHydration.shouldFetchContent(
        isDirectory: false,
        suppliedContentURL: nil,
        expectedSHA256: "abc"
      )
    )
  }

  @Test func zeroBytePlaceholdersMustFetch() throws {
    let url = try writeTempFile(Data())
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    #expect(
      FileProviderHydration.shouldFetchContent(
        isDirectory: false,
        suppliedContentURL: url,
        expectedSHA256: ""
      )
    )
    #expect(
      FileProviderHydration.shouldFetchContent(
        isDirectory: false,
        suppliedContentURL: url,
        expectedSHA256: "deadbeef"
      )
    )
  }

  @Test func matchingHashSkipsFetch() throws {
    let data = Data("%PDF-1.4".utf8)
    let url = try writeTempFile(data)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let sha = SHA256File.hex(of: data)
    #expect(
      !FileProviderHydration.shouldFetchContent(
        isDirectory: false,
        suppliedContentURL: url,
        expectedSHA256: sha
      )
    )
  }

  @Test func stagesUnderUniqueDirectory() {
    let root = URL(fileURLWithPath: "/tmp/fp", isDirectory: true)
    let first = FileProviderHydration.stagingFileURL(
      in: root,
      filename: "faktura_104.pdf",
      unique: "a"
    )
    let second = FileProviderHydration.stagingFileURL(
      in: root,
      filename: "faktura_104.pdf",
      unique: "b"
    )
    #expect(first.lastPathComponent == "faktura_104.pdf")
    #expect(first.deletingLastPathComponent().lastPathComponent == "a")
    #expect(first != second)
  }

  func writeTempFile(_ data: Data) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("item.pdf")
    try data.write(to: url)
    return url
  }
}
