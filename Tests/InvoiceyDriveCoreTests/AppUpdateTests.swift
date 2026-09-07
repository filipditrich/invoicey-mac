import Foundation
import InvoiceyDriveCore
import Testing

struct AppVersionTests {
  @Test func normalizesLeadingV() {
    #expect(AppVersion.normalize("v0.1.4") == "0.1.4")
    #expect(AppVersion.normalize(" V0.1.10 ") == "0.1.10")
    #expect(AppVersion.normalize("0.1.4") == "0.1.4")
  }

  @Test func rejectsNonSemver() {
    #expect(AppVersion.normalize("") == nil)
    #expect(AppVersion.normalize("latest") == nil)
  }

  @Test func comparesNumericParts() {
    #expect(AppVersion.isNewer("0.1.5", than: "0.1.4"))
    #expect(AppVersion.isNewer("0.2.0", than: "0.1.10"))
    #expect(!AppVersion.isNewer("0.1.4", than: "0.1.4"))
    #expect(!AppVersion.isNewer("0.1.4", than: "0.1.5"))
    #expect(AppVersion.isNewer("v0.1.5", than: "0.1.4"))
  }
}

struct AppUpdatePolicyTests {
  @Test func availableWhenFeedIsNewer() throws {
    let latest = try DriveLatestRelease.parse(
      Data("""
      {"version":"0.1.5","dmgUrl":"https://example.com/InvoiceyDrive.dmg"}
      """.utf8)
    )
    #expect(
      AppUpdatePolicy.outcome(current: "0.1.4", latest: latest)
        == .available(current: "0.1.4", latest: latest)
    )
  }

  @Test func upToDateWhenInstalledMatchesOrIsNewer() throws {
    let latest = try DriveLatestRelease.parse(
      Data("""
      {"version":"0.1.4","dmgUrl":"https://example.com/InvoiceyDrive.dmg"}
      """.utf8)
    )
    #expect(AppUpdatePolicy.outcome(current: "0.1.4", latest: latest) == .upToDate(current: "0.1.4"))
    #expect(AppUpdatePolicy.outcome(current: "0.1.5", latest: latest) == .upToDate(current: "0.1.5"))
  }

  @Test func unknownWhenThisBuildHasNoVersion() throws {
    let latest = try DriveLatestRelease.parse(
      Data("""
      {"version":"0.1.4","dmgUrl":"https://example.com/InvoiceyDrive.dmg"}
      """.utf8)
    )
    #expect(AppUpdatePolicy.outcome(current: nil, latest: latest) == .unknown)
    #expect(AppUpdatePolicy.outcome(current: "", latest: latest) == .unknown)
  }

  @Test func automaticCheckIsDueOncePerDay() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(AppUpdatePolicy.isAutomaticDue(lastCheckedAt: nil, now: now))
    #expect(
      AppUpdatePolicy.isAutomaticDue(
        lastCheckedAt: now.addingTimeInterval(-86_400),
        now: now
      )
    )
    #expect(
      !AppUpdatePolicy.isAutomaticDue(
        lastCheckedAt: now.addingTimeInterval(-3_600),
        now: now
      )
    )
  }
}

struct UpdateCheckStoreTests {
  @Test func persistsLastCheckedAt() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = UpdateCheckStore(
      fileURL: dir.appendingPathComponent("update-check.json")
    )
    #expect(try store.load().lastCheckedAt == nil)
    let checked = Date(timeIntervalSince1970: 1_800_000_000)
    try store.markChecked(at: checked)
    let loaded = try store.load().lastCheckedAt
    #expect(loaded != nil)
    #expect(abs((loaded?.timeIntervalSince1970 ?? 0) - 1_800_000_000) < 1)
  }
}
