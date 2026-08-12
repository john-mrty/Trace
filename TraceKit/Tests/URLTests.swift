//
//  URLTests.swift
//

import MarkEditKit
import XCTest

final class URLTests: XCTestCase {
  func testResolvingRelativeSymbolicLink() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let targetDirectory = directory.appending(path: "real", directoryHint: .isDirectory)
    let target = targetDirectory.appending(path: "target.md", directoryHint: .notDirectory)
    let link = directory.appending(path: "note", directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
    try Data("# Note".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(
      atPath: link.path(percentEncoded: false),
      withDestinationPath: "real/target.md"
    )

    XCTAssertEqual(link.resolvingSymbolicLink, target)
    XCTAssertFalse(link.resolvingSymbolicLink.isBinaryFile)
  }

  func testResolvingSymbolicLinkInParentPath() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let targetDirectory = directory.appending(path: "real", directoryHint: .isDirectory)
    let target = targetDirectory.appending(path: "target.md", directoryHint: .notDirectory)
    let link = directory.appending(path: "alias", directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
    try Data("# Note".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(
      atPath: link.path(percentEncoded: false),
      withDestinationPath: "real"
    )

    XCTAssertEqual(
      link.appending(path: "target.md", directoryHint: .notDirectory).resolvingSymbolicLink,
      target
    )
  }
}

// MARK: - Private

private extension URLTests {
  func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .resolvingSymlinksInPath()
      .appending(path: "URLTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
