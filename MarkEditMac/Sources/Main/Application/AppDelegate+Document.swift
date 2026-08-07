//
//  AppDelegate+Document.swift
//  MarkEditMac
//
//  Created by cyan on 1/15/23.
//

import AppKit

@MainActor
extension AppDelegate {
  var currentDocument: EditorDocument? {
    currentEditor?.document
  }

  var currentEditor: EditorViewController? {
    NSApp.currentEditor
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    guard shouldOpenOrCreateDocument() else {
      return false
    }

    // The very first launch opens the manual as a document instead of the welcome window
    if !UserDefaults.standard.bool(forKey: Self.manualOpenedKey) {
      UserDefaults.standard.set(true, forKey: Self.manualOpenedKey)
      createNewFile(fileName: "Welcome to Trace", initialContent: Self.welcomeManual)
      return false
    }

    showWelcomeWindow()
    return false
  }

  @IBAction func openWelcomeManual(_ sender: Any?) {
    createNewFile(fileName: "Welcome to Trace", initialContent: Self.welcomeManual)
  }

  func showWelcomeWindow() {
    if welcomeWindowController == nil {
      welcomeWindowController = WelcomeWindowController()
    }

    welcomeWindowController?.refreshRecentDocuments()
    welcomeWindowController?.window?.center()
    welcomeWindowController?.showWindow(self)
  }

  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()

    // Only show the secondary option based on the preference
    switch AppPreferences.General.newWindowBehavior {
    case .openDocument:
      menu.addItem(withTitle: Localized.Document.newDocument) {
        NSDocumentController.shared.newDocument(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    case .newDocument:
      menu.addItem(withTitle: Localized.Document.openDocument) {
        sender.showOpenPanel()
      }
    }

    return menu
  }

  func createNewFile(fileName: String? = nil, initialContent: String? = nil, isIntent: Bool = false) {
    // In EditorDocument, this is used as an external filename
    AppDocumentController.suggestedFilename = fileName

    // Activating the app also creates a new file if new window behavior is `newDocument`,
    // prevent duplicate creation from Shortcuts like `CreateNewDocumentIntent`.
    if !isIntent || (Date.timeIntervalSinceReferenceDate - States.untitledFileOpenedDate > 0.2) {
      NSDocumentController.shared.newDocument(nil)
    }

    if isIntent {
      NSApp.activate(ignoringOtherApps: true)
    }

    if let initialContent {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.currentEditor?.prepareInitialContent(initialContent)
      }
    }
  }

  func openFile(queryDict: [String: String]?) {
    if let filePath = queryDict?["path"] {
      NSWorkspace.shared.openOrReveal(url: URL(filePath: filePath))
    } else {
      NSApp.showOpenPanel()
    }
  }

  func createNewFile(queryDict: [String: String]?) {
    let fileName = queryDict?["filename"]
    let initialContent = queryDict?["initial-content"]
    createNewFile(fileName: fileName, initialContent: initialContent)
  }

  func toggleDocumentWindowVisibility() {
    // Order out immaterial windows like settings, about...
    for window in NSApp.windows where !(window is EditorWindow) {
      window.orderOut(nil)
    }

    let windows = NSApp.windows.filter {
      $0 is EditorWindow
    }

    if windows.isEmpty {
      // Open a new window if we don't have any editor windows
      openOrCreateDocument(sender: NSApp)
    } else if (windows.contains { $0.isKeyWindow }) {
      // Hide the app if there was already a key editor window
      NSApp.hide(nil)
    } else {
      // Ensure one editor window is key and ordered front, if exists, called after NSApp.activate
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        let windows = NSApp.windows.filter { $0 is EditorWindow }
        if windows.allSatisfy({ !$0.isKeyWindow }) {
          windows.first?.makeKeyAndOrderFront(nil)
        }
      }
    }

    NSApp.activate(ignoringOtherApps: true)
  }

  /// Summons/dismisses the editor as a right-edge overlay (Option+`, Ghostty-style).
  func toggleOverlay() {
    let editors = NSApp.windows.compactMap { $0 as? EditorWindow }

    // Already overlaying and focused → dismiss, then hide once the slide-out finishes
    // so the animation isn't cut short by the app disappearing mid-flight.
    if let overlaying = editors.first(where: { $0.overlayMode && $0.isKeyWindow }) {
      overlaying.exitOverlayMode(animated: true) {
        NSApp.hide(nil)
      }
      return
    }

    // No editor window → create one, then overlay once it exists.
    guard let target = editors.first(where: { $0.isKeyWindow }) ?? editors.first else {
      openOrCreateDocument(sender: NSApp)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        NSApp.activate(ignoringOtherApps: true)
        (NSApp.windows.compactMap { $0 as? EditorWindow }.first)?.enterOverlayMode(animated: true)
      }
      return
    }

    NSApp.activate(ignoringOtherApps: true)
    target.enterOverlayMode(animated: true)
  }
}

// MARK: - Welcome Window

/// Shown on launch (and dock re-activation) when no document is open:
/// create a new document, open one, or jump back into a recent file.
@MainActor
final class WelcomeWindowController: NSWindowController {
  private let recentsStackView = NSStackView()
  private var observation: NSObjectProtocol?

  convenience init() {
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 0),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    self.init(window: window)

    window.contentView = createContentView()

    // Dismiss once any editor window takes over, no matter how it was opened
    observation = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeMainNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard notification.object is EditorWindow else {
        return
      }

      Task { @MainActor in
        self?.close()
      }
    }
  }

  func refreshRecentDocuments() {
    recentsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let recentURLs = NSDocumentController.shared.recentDocumentURLs.prefix(5)

    guard !recentURLs.isEmpty else {
      let emptyLabel = NSTextField(labelWithString: String(localized: "No recent documents"))
      emptyLabel.font = .systemFont(ofSize: 12)
      emptyLabel.textColor = .tertiaryLabelColor
      recentsStackView.addArrangedSubview(emptyLabel)
      return
    }

    for url in recentURLs {
      let button = NSButton()
      button.isBordered = false
      button.imagePosition = .imageLeading
      button.alignment = .left
      button.image = NSWorkspace.shared.icon(forFile: url.path)
      button.image?.size = CGSize(width: 16, height: 16)
      button.attributedTitle = NSAttributedString(
        string: url.deletingPathExtension().lastPathComponent,
        attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
      )
      button.toolTip = url.path
      button.target = self
      button.action = #selector(openRecentDocument(_:))
      button.identifier = NSUserInterfaceItemIdentifier(url.path)
      recentsStackView.addArrangedSubview(button)
    }
  }
}

// MARK: - Private

private extension WelcomeWindowController {
  func createContentView() -> NSView {
    let iconView = NSImageView(image: NSApp.applicationIconImage)
    iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
    iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true

    let titleLabel = NSTextField(labelWithString: "Trace")
    titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let versionLabel = NSTextField(labelWithString: String(localized: "Version \(version)"))
    versionLabel.font = .systemFont(ofSize: 12)
    versionLabel.textColor = .secondaryLabelColor

    let newButton = NSButton(
      title: Localized.Document.newDocument,
      target: self,
      action: #selector(createNewDocument(_:))
    )
    newButton.bezelStyle = .rounded
    newButton.controlSize = .large
    newButton.keyEquivalent = "\r"

    let openButton = NSButton(
      title: Localized.Document.openDocument,
      target: self,
      action: #selector(openExistingDocument(_:))
    )
    openButton.bezelStyle = .rounded
    openButton.controlSize = .large

    let buttonsStackView = NSStackView(views: [newButton, openButton])
    buttonsStackView.orientation = .horizontal
    buttonsStackView.spacing = 10

    recentsStackView.orientation = .vertical
    recentsStackView.alignment = .leading
    recentsStackView.spacing = 8

    let stackView = NSStackView(views: [
      iconView,
      titleLabel,
      versionLabel,
      buttonsStackView,
      recentsStackView,
    ])

    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.spacing = 8
    stackView.setCustomSpacing(2, after: titleLabel)
    stackView.setCustomSpacing(24, after: versionLabel)
    stackView.setCustomSpacing(28, after: buttonsStackView)
    stackView.edgeInsets = NSEdgeInsets(top: 36, left: 48, bottom: 36, right: 48)

    let contentView = NSView()
    contentView.addSubview(stackView)
    stackView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
      stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
    ])

    return contentView
  }

  @objc func createNewDocument(_ sender: NSButton) {
    close()
    NSDocumentController.shared.newDocument(nil)
  }

  @objc func openExistingDocument(_ sender: NSButton) {
    close()
    NSApp.showOpenPanel()
  }

  @objc func openRecentDocument(_ sender: NSButton) {
    guard let path = sender.identifier?.rawValue else {
      return
    }

    close()
    NSDocumentController.shared.openDocument(
      withContentsOf: URL(filePath: path),
      display: true
    ) { _, _, _ in }
  }
}

// MARK: - Private

private extension AppDelegate {
  enum States {
    @MainActor static var openPanelShownDate: TimeInterval = 0
    @MainActor static var untitledFileOpenedDate: TimeInterval = 0
  }

  @discardableResult
  func openOrCreateDocument(sender: NSApplication) -> Bool {
    switch AppPreferences.General.newWindowBehavior {
    case .openDocument:
      // The system occasionally runs this twice in a row, prevent duplicate panels
      let currentDate = Date.timeIntervalSinceReferenceDate
      if currentDate - States.openPanelShownDate > 0.2 {
        States.openPanelShownDate = currentDate
        sender.showOpenPanel()
      }

      return false
    case .newDocument:
      States.untitledFileOpenedDate = Date.timeIntervalSinceReferenceDate
      return true
    }
  }
}

// MARK: - Welcome Manual

private extension AppDelegate {
  static let manualOpenedKey = "trace.manual.opened"

  static let welcomeManual = """
  # Welcome to Trace

  *A quiet place to write.*

  This document is the quickstart. It's also just a Markdown file — edit it, save it, or close it and never see it again. Reopen it anytime from **Help → Welcome to Trace**.

  ## The idea

  Trace hides Markdown syntax as you write. Type `**bold**` and the asterisks vanish, leaving **bold**. Type `#` and a space to make an editable heading. Links become clickable text, checkboxes become real checkboxes, code fences become panels. The words are the interface.

  ## Five things to try first

  1. **⇧⌘H** — show the plumbing. Syntax marks, line numbers, and a selection counter appear; it doubles as a source mode. Press again to write.
  2. **⇧⌘F** — focus mode. Everything dims except the lines you're working on, and typewriter scrolling holds the caret at the center of the screen. The text moves, you don't.
  3. **⌘K** — the command palette. Every action, searchable: type "dark" to switch appearance, "focus" to toggle focus mode. Recent files live there too.
  4. **Hover the dashes in the top-left** — that's the table of contents. It marks your place; click any entry to jump.
  5. **⌥`** — overlay mode. This document floats over your other apps as a right-edge panel, for notes alongside your work.

  ## Where everything lives

  | Shortcut | Does |
  | --- | --- |
  | ⌘K | Command palette — every action, searchable |
  | ⇧⌘O | Open Document — fuzzy-find any Markdown file nearby, or a recent one |
  | ⇧⌘H | Show or hide Markdown syntax |
  | ⇧⌘F | Focus mode, with typewriter scrolling |
  | ⌥⌘C | Copy as Rich Text — paste into Mail, Docs, or Slack with formatting intact |
  | ⌥` | Overlay mode — float this document over your other apps |
  | ⌘, | Settings — accent colors, line height, appearance |

  The small capsule at the bottom holds the rest: headings, emphasis, lists, syntax, focus, and statistics. It fades while you type and returns when you reach for the mouse.

  ## Lists

  * Bulleted lists use stars and render as round bullets
  - Dashed lists use hyphens and stay dashes

  1. Ordered lists
  2. Number themselves

  - [ ] And todos have checkboxes
  - [x] That strike through when done

  ## When the writing leaves Trace

  **⌥⌘C** copies the selection — or the whole document — as rich text: real headings, links, and emphasis land intact in Mail, Google Docs, Slack, or Notes. A plain paste still gives you the Markdown source. And your file is just plain text on disk — no library, no lock-in.

  ---

  That rule above? Just three dashes. Enjoy the quiet.
  """
}
