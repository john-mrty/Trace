//
//  AppDocumentController.swift
//  MarkEditMac
//
//  Created by cyan on 10/14/24.
//

import AppKit
import AppKitExtensions
import MarkEditCore
import MarkEditKit

/**
 Subclass of `NSDocumentController` to allow customizations.

 NSDocumentController.shared will be an instance of `AppDocumentController` at runtime.
 */
final class AppDocumentController: NSDocumentController {
  static var suggestedTextEncoding: EditorTextEncoding?
  static var suggestedFilename: String?
  private var isSavingAllDocuments = false

  override var hasEditedDocuments: Bool {
    super.hasEditedDocuments || editorDocuments.contains { $0.isOutdated }
  }

  override func reviewUnsavedDocuments(
    withAlertTitle title: String?,
    cancellable: Bool,
    delegate: Any?,
    didReviewAllSelector: Selector?,
    contextInfo: UnsafeMutableRawPointer?
  ) {
    // AppKit calls this before applicationShouldTerminate, including for drafts
    // whose edits have already been autosaved to a temporary location.
    let alert = NSAlert()
    alert.messageText = String(localized: "Save changes before quitting?")
    alert.informativeText = String(localized: "Save all open documents before quitting. Choose one folder for untitled documents; filenames will be assigned automatically.")
    alert.addButton(withTitle: String(localized: "Save All and Quit"))
    alert.addButton(withTitle: String(localized: "Review Changes…"))
    if cancellable {
      alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
    }

    let finish: (Bool) -> Void = { reviewed in
      guard let target = delegate as? NSObject, let selector = didReviewAllSelector else {
        return
      }

      // AppKit's delegate callback has a documented three-argument signature.
      typealias ReviewCallback = @convention(c) (
        AnyObject, Selector, NSDocumentController, Bool, UnsafeMutableRawPointer?
      ) -> Void
      let callback = unsafeBitCast(target.method(for: selector), to: ReviewCallback.self)
      callback(target, selector, self, reviewed, contextInfo)
    }

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      Task { @MainActor in
        finish(await self.saveAllOpenDocuments())
      }
    case .alertSecondButtonReturn:
      // Go directly to each document's review, skipping the system summary alert.
      super.closeAllDocuments(
        withDelegate: delegate,
        didCloseAllSelector: didReviewAllSelector,
        contextInfo: contextInfo
      )
    default:
      finish(false)
    }
  }

  /// Pick a destination once, then save every document without individual Save panels.
  func saveAllOpenDocuments() async -> Bool {
    guard !isSavingAllDocuments else {
      return false
    }

    isSavingAllDocuments = true
    defer { isSavingAllDocuments = false }

    do {
      var destination: URL?
      if let defaultDirectory = try quitSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Save All Documents")
        panel.message = String(localized: "Choose a folder for all untitled documents. Each document will be given its own filename.")
        panel.prompt = String(localized: "Save All")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultDirectory
        guard await panel.begin() == .OK, let directory = panel.url else {
          return false
        }
        destination = directory
      }

      for document in documents {
        guard document.fileURL == nil || document.isDocumentEdited
          || (document as? EditorDocument)?.isOutdated == true else {
          continue
        }

        if let editorDocument = document as? EditorDocument {
          await editorDocument.prepareForExplicitSave()
        }

        let isUntitled = document.fileURL == nil
        let type = document.fileType ?? AppPreferences.General.newFilenameExtension.exportedType
        let url: URL
        if let existingURL = document.fileURL {
          url = existingURL
        } else if let destination {
          let fileExtension = document.fileNameExtension(forType: type, saveOperation: .saveAsOperation)
            ?? AppPreferences.General.newFilenameExtension.rawValue
          url = availableSaveURL(for: document, in: destination, fileExtension: fileExtension)
        } else {
          return false
        }

        try await document.save(to: url, ofType: type, for: isUntitled ? .saveAsOperation : .saveOperation)
        noteNewRecentDocumentURL(url)
      }

      return true
    } catch {
      presentError(error)
      return false
    }
  }

  override var maximumRecentDocumentCount: Int {
    min(super.maximumRecentDocumentCount, 8)
  }

  override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?) async -> Int {
    if let defaultDirectory = AppRuntimeConfig.defaultOpenDirectory {
      setOpenPanelDirectory(defaultDirectory)
    }

    if AppRuntimeConfig.disableOpenPanelOptions {
      openPanel.accessoryView = nil
    } else {
      openPanel.accessoryView = EditorSaveOptionsView.wrapper(for: .openPanel) { [weak openPanel] result in
        switch result {
        case .textEncoding(let value):
          Self.suggestedTextEncoding = value
        case .showHiddenFiles(let value):
          openPanel?.showsHiddenFiles = value
        default:
          Logger.assertFail("Invalid change: \(result)")
        }
      }
    }

    Self.suggestedTextEncoding = nil
    openPanel.showsHiddenFiles = AppPreferences.General.showHiddenFiles
    openPanel.relayoutAccessoryView()

    let onBecomeActive = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.appearanceDidChange(isAppActive: true)
      }
    }

    let onResignActive = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.appearanceDidChange(isAppActive: false)
      }
    }

    let appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
      Task { @MainActor in
        self?.appearanceDidChange()
      }
    }

    defer {
      NotificationCenter.default.removeObserver(onBecomeActive)
      NotificationCenter.default.removeObserver(onResignActive)
      appearanceObservation.invalidate()
      UserDefaults.forcedColorScheme = .system
    }

    appearanceDidChange()
    return await super.beginOpenPanel(openPanel, forTypes: inTypes)
  }

  override func openDocument(
    withContentsOf url: URL,
    display displayDocument: Bool,
    completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
  ) {
    let resolvedURL = url.resolvingSymbolicLink

    if resolvedURL.isBinaryFile {
      // Dead loop prevention
      if Bundle.main.isDefaultApp(toOpen: resolvedURL) {
        NSWorkspace.shared.activateFileViewerSelecting([resolvedURL])
      } else {
        NSWorkspace.shared.open(resolvedURL)
      }

      // Ignore the default opening logic
      return completionHandler(nil, false, nil)
    }

    Task { @MainActor in
      // Ensure the preloader has a fully loaded editor before opening the document
      await EditorPreloader.shared.prepareViewController()

      super.openDocument(
        withContentsOf: resolvedURL,
        display: displayDocument,
        completionHandler: completionHandler
      )
    }
  }

  override func saveAllDocuments(_ sender: Any?) {
    Task { @MainActor in
      _ = await saveAllOpenDocuments()
    }
  }
}

// MARK: - Private

private extension AppDocumentController {
  func availableSaveURL(for document: NSDocument, in directory: URL, fileExtension: String) -> URL {
    let name = (document.displayName ?? "Untitled")
      .components(separatedBy: CharacterSet(charactersIn: "/:").union(.controlCharacters))
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let suffix = "." + fileExtension
    let stem = name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
    let base = String((stem.isEmpty ? "Untitled" : stem).prefix(120))
    var candidate = directory.appendingPathComponent(base).appendingPathExtension(fileExtension)
    var number = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = directory.appendingPathComponent("\(base) \(number)").appendingPathExtension(fileExtension)
      number += 1
    }
    return candidate
  }

  func quitSaveDirectory() throws -> URL? {
    guard documents.contains(where: { $0.fileURL == nil }) else {
      return nil
    }

    let fileManager = FileManager.default
    let cloudDrive = fileManager.homeDirectoryForCurrentUser.appending(
      path: "Library/Mobile Documents/com~apple~CloudDocs",
      directoryHint: .isDirectory
    )
    let documentsDirectory = fileManager.fileExists(atPath: cloudDrive.path)
      ? cloudDrive.appending(path: "Documents", directoryHint: .isDirectory)
      : fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let directory = documentsDirectory.appending(path: "Trace", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  func appearanceDidChange(isAppActive: Bool = NSApp.isActive) {
    guard isAppActive else {
      UserDefaults.forcedColorScheme = .system
      return
    }

    switch AppPreferences.General.appearance {
    case .system:
      UserDefaults.forcedColorScheme = .system
    case .light:
      UserDefaults.forcedColorScheme = .light
    case .dark:
      UserDefaults.forcedColorScheme = .dark
    }
  }
}

private extension NSOpenPanel {
  /// Re-layouts the accessory view to work around internal AppKit bugs.
  ///
  /// For example, the animation of opening documents will sometimes be skipped.
  func relayoutAccessoryView() {
    accessoryView?.needsLayout = true
  }
}
