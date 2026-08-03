//
//  ExtensionCoreTests.swift
//
//  Created by cyan on 7/12/26.
//

import XCTest
@testable import ExtensionCore

final class ExtensionCoreTests: XCTestCase {

  // MARK: - identifier(fromFileName:)

  func testIdentifierFromFileName() {
    XCTAssertEqual(ExtensionConfig.identifier(fromFileName: "markedit-preview.js"), "markedit-preview")
    XCTAssertEqual(ExtensionConfig.identifier(fromFileName: "My_Cool Extension.js"), "my-cool-extension")
    XCTAssertEqual(ExtensionConfig.identifier(fromFileName: "Foo!!Bar.js"), "foo-bar")
  }

  func testIdentifierFallsBackWhenEmpty() {
    XCTAssertEqual(ExtensionConfig.identifier(fromFileName: "___.js"), "extension")
  }

  // MARK: - Installed

  func testInstalledAdoptingFileCapturesLocalFields() throws {
    let dir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let fileURL = dir.appending(path: "MarkEdit-Preview.js", directoryHint: .notDirectory)
    try Data("console.log('hi')".utf8).write(to: fileURL)

    let installed = ExtensionConfig.Installed(adopting: fileURL)
    XCTAssertEqual(installed.id, "markedit-preview")
    XCTAssertEqual(installed.file, "MarkEdit-Preview.js")
    XCTAssertTrue(installed.enabled ?? false)
    XCTAssertEqual(installed.sha256?.count, 64)
    XCTAssertNotNil(installed.installDate)
    // Not derivable locally, filled later by the registry
    XCTAssertNil(installed.version)
    XCTAssertNil(installed.url)
  }

  func testMergingPreservesUserManagedFields() {
    let previous = ExtensionConfig.Installed(
      id: "sample",
      version: "1.0.0",
      url: "https://example.com/old.js",
      sha256: "old",
      file: "sample.js",
      enabled: false,
      installDate: "2026-01-01T00:00:00Z"
    )

    let fresh = ExtensionConfig.Installed(
      id: "sample",
      version: "2.0.0",
      url: "https://example.com/new.js",
      sha256: "new",
      file: "sample.js",
      enabled: true,
      installDate: "2026-07-12T00:00:00Z"
    )

    let merged = fresh.merging(preserving: previous)
    // New download wins for version/url/sha256
    XCTAssertEqual(merged.version, "2.0.0")
    XCTAssertEqual(merged.url, "https://example.com/new.js")
    XCTAssertEqual(merged.sha256, "new")
    // Previous wins for the user-managed enabled flag and the original installDate
    XCTAssertEqual(merged.installDate, "2026-01-01T00:00:00Z")
    XCTAssertFalse(merged.enabled ?? true)
  }

  // MARK: - upsertInstalled

  func testUpsertUpdatesInPlaceAndAppendsNew() throws {
    let dir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(at: dir)
      ExtensionEnvironment.documentsDirectory = URL.documentsDirectory
    }

    ExtensionEnvironment.documentsDirectory = dir
    try seedExtensions(ids: ["a", "b", "c"], in: dir)

    // Updating an existing id keeps its injection position
    ExtensionConfig.upsertInstalled(makeInstalled(id: "b", version: "2.0.0"))
    XCTAssertEqual(installedIds(in: dir), ["a", "b", "c"])

    // A new id is appended
    ExtensionConfig.upsertInstalled(makeInstalled(id: "d", version: "1.0.0"))
    XCTAssertEqual(installedIds(in: dir), ["a", "b", "c", "d"])
  }

  // MARK: - setEnabled

  func testSetEnabledTogglesFlagInPlace() throws {
    let dir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(at: dir)
      ExtensionEnvironment.documentsDirectory = URL.documentsDirectory
    }

    ExtensionEnvironment.documentsDirectory = dir
    try seedExtensions(ids: ["a", "b", "c"], in: dir)

    // Absent flag means enabled
    XCTAssertNil(installedRecord(id: "b", in: dir)?["enabled"])

    ExtensionConfig.setEnabled(false, forID: "b")
    XCTAssertEqual(installedRecord(id: "b", in: dir)?["enabled"] as? Bool, false)

    // Order is preserved and siblings are untouched
    XCTAssertEqual(installedIds(in: dir), ["a", "b", "c"])
    XCTAssertNil(installedRecord(id: "a", in: dir)?["enabled"])

    ExtensionConfig.setEnabled(true, forID: "b")
    XCTAssertEqual(installedRecord(id: "b", in: dir)?["enabled"] as? Bool, true)
  }

  func testSetEnabledIgnoresUnknownIdentifier() throws {
    let dir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(at: dir)
      ExtensionEnvironment.documentsDirectory = URL.documentsDirectory
    }

    ExtensionEnvironment.documentsDirectory = dir
    try seedExtensions(ids: ["a"], in: dir)

    ExtensionConfig.setEnabled(false, forID: "missing")
    XCTAssertEqual(installedIds(in: dir), ["a"])
    XCTAssertNil(installedRecord(id: "a", in: dir)?["enabled"])
  }

  // MARK: - remove

  func testRemoveDropsRecordOnly() throws {
    let dir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(at: dir)
      ExtensionEnvironment.documentsDirectory = URL.documentsDirectory
    }

    ExtensionEnvironment.documentsDirectory = dir
    try seedExtensions(ids: ["a", "b", "c"], in: dir)

    ExtensionConfig.remove(id: "b")
    XCTAssertEqual(installedIds(in: dir), ["a", "c"])

    // Removing an unknown id is a no-op
    ExtensionConfig.remove(id: "missing")
    XCTAssertEqual(installedIds(in: dir), ["a", "c"])
  }

  // MARK: - reorder

  func testReorderChangesInjectionOrder() throws {
    let dir = try makeTempDir()
    defer {
      try? FileManager.default.removeItem(at: dir)
      ExtensionEnvironment.documentsDirectory = URL.documentsDirectory
    }

    ExtensionEnvironment.documentsDirectory = dir
    try seedExtensions(ids: ["a", "b", "c"], in: dir)

    ExtensionConfig.reorder(orderedIDs: ["c", "a", "b"])
    XCTAssertEqual(installedIds(in: dir), ["c", "a", "b"])

    // Ids missing from the new order keep their relative position at the end
    ExtensionConfig.reorder(orderedIDs: ["b"])
    XCTAssertEqual(installedIds(in: dir), ["b", "c", "a"])
  }
}

// MARK: - Private

private extension ExtensionCoreTests {
  func makeInstalled(
    id: String,
    version: String?
  ) -> ExtensionConfig.Installed {
    ExtensionConfig.Installed(
      id: id,
      version: version,
      url: nil,
      sha256: nil,
      file: "\(id).js",
      enabled: nil,
      installDate: nil
    )
  }

  func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "ExtensionCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  func seedExtensions(ids: [String], in dir: URL) throws {
    let installed = ids.map { "{ \"id\": \"\($0)\", \"file\": \"\($0).js\" }" }.joined(separator: ",\n")
    let json = "{ \"installed\": [\n\(installed)\n] }"
    try Data(json.utf8).write(to: dir.appending(path: "extensions.json", directoryHint: .notDirectory))
  }

  func installedIds(in dir: URL) -> [String] {
    let url = dir.appending(path: "extensions.json", directoryHint: .notDirectory)
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let installed = object["installed"] as? [[String: Any]] else {
      return []
    }

    return installed.compactMap { $0["id"] as? String }
  }

  func installedRecord(id: String, in dir: URL) -> [String: Any]? {
    let url = dir.appending(path: "extensions.json", directoryHint: .notDirectory)
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let installed = object["installed"] as? [[String: Any]] else {
      return nil
    }

    return installed.first { $0["id"] as? String == id }
  }
}
