//
//  AppDelegate+FileSystem.swift
//  MarkEditMac
//
//  Created by cyan on 4/30/24.
//

import AppKit
import MarkEditKit

extension AppDelegate {
  func saveGrantedFolderAsBookmark() async {
    let openPanel = NSOpenPanel()
    openPanel.prompt = Localized.General.grantAccess
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = false
    openPanel.allowsMultipleSelection = false

    guard await openPanel.begin() == .OK, let url = openPanel.url else {
      return
    }

    guard let newBookmark = try? url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) else {
      return Logger.log(.error, "Failed to create bookmark data")
    }

    let bookmarkData = AppPreferences.General.grantedFolderBookmark
    let bookmarkList: [Data] = {
      if let dataArray = bookmarkData?.decodeToDataArray() {
        return dataArray
      }

      if let bookmarkData {
        return [bookmarkData]
      }

      return []
    }()

    let encodedData = bookmarkList.appendingData(newBookmark).encodeToData()
    AppPreferences.General.grantedFolderBookmark = encodedData
  }

  /// Picks the sidebar root folder and persists it as a security-scoped bookmark.
  /// Also appended to the granted-folder list so opening documents under it stays sandbox-clean.
  func saveSidebarRootBookmark() async {
    let openPanel = NSOpenPanel()
    openPanel.prompt = Localized.General.grantAccess
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = false
    openPanel.allowsMultipleSelection = false

    guard await openPanel.begin() == .OK, let url = openPanel.url else {
      return
    }

    guard let bookmark = try? url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) else {
      return Logger.log(.error, "Failed to create bookmark data")
    }

    AppPreferences.General.sidebarRootBookmark = bookmark
    _ = url.startAccessingSecurityScopedResource()

    let grantedList = AppPreferences.General.grantedFolderBookmark?.decodeToDataArray()
      ?? AppPreferences.General.grantedFolderBookmark.map { [$0] }
      ?? []
    AppPreferences.General.grantedFolderBookmark = grantedList.appendingData(bookmark).encodeToData()

    for editor in EditorPreloader.shared.viewControllers() {
      editor.reloadSidebar()
    }
  }

  /// Resolves the persisted sidebar root, starting security-scope access as a side effect.
  static func resolvedSidebarRootURL() -> URL? {
    guard let bookmarkData = AppPreferences.General.sidebarRootBookmark else {
      return nil
    }

    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: bookmarkData,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      Logger.log(.error, "Failed to resolve sidebar root bookmark")
      return nil
    }

    _ = url.startAccessingSecurityScopedResource()
    return url
  }

  func startAccessingGrantedFolder() {
    guard let bookmarkData = AppPreferences.General.grantedFolderBookmark else {
      return
    }

    if let bookmarkList = bookmarkData.decodeToDataArray() {
      bookmarkList.forEach {
        startAccessingBookmarkData($0)
      }
    } else {
      startAccessingBookmarkData(bookmarkData)
    }
  }
}

// MARK: - Private

private extension AppDelegate {
  func startAccessingBookmarkData(_ bookmarkData: Data) {
    do {
      var isStale = false
      let bookmarkURL = try URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if !bookmarkURL.startAccessingSecurityScopedResource() {
        Logger.log(.error, "Failed to start accessing security scoped resource")
      }
    } catch {
      Logger.log(.error, "Failed to resolve bookmark data")
    }
  }
}
