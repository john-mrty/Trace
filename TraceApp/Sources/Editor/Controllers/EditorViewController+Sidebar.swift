//
//  EditorViewController+Sidebar.swift
//  MarkEditMac
//
//  Created by cyan on 8/9/26.
//

import AppKit
import AppKitExtensions
import SharedUI

/**
 Obsidian-style file navigation sidebar: one root folder, writing files only.

 Visibility is a global preference so every window (tab) stays in sync; the
 tree view and its expansion state are per-window.
 */
extension EditorViewController {
  static let sidebarWidth: Double = 240

  var sidebarRootURL: URL? {
    AppDelegate.resolvedSidebarRootURL() ?? document?.fileURL?.deletingLastPathComponent()
  }

  @IBAction func toggleFileSidebar(_ sender: Any?) {
    AppPreferences.Window.showSidebar.toggle()
  }

  func setSidebarVisible(_ visible: Bool, animated: Bool) {
    guard isSidebarVisible != visible else {
      return
    }

    // The overlay is 1/3 screen width; a tree panel there is useless
    if visible, (view.window as? EditorWindow)?.overlayMode == true {
      return
    }

    isSidebarVisible = visible
    // Hide the button, not the accessory: accessory-level isHidden is
    // unreliable around install time and shifts the title while animating
    sidebarSortButton.isHidden = !visible
    if visible {
      reloadSidebar()
    }

    // Arrow keys navigate the tree right after opening (Obsidian-style);
    // animated == true means a user toggle rather than launch/overlay seeding
    if animated, view.window?.isKeyWindow == true {
      if visible {
        fileTree.focus()
      } else {
        view.window?.makeFirstResponder(webView)
      }
    }

    guard animated, !AppDesign.reduceMotion, view.window != nil else {
      contentLeftInset = visible ? Self.sidebarWidth : 0
      sidebarContainer.isHidden = !visible
      updateSidebarFabOffset(animated: false)
      layoutSidebar()
      layoutWebView()
      layoutPanels()
      return
    }

    let width = Self.sidebarWidth
    hasUnfinishedAnimations = true

    if visible {
      sidebarContainer.isHidden = false
      sidebarContainer.frame = sidebarFrame(offscreen: true)
    } else {
      // Pre-expand so the editor covers the full width while it slides back
      webView.frame.size.width = view.bounds.width
    }

    updateSidebarFabOffset(animated: true)
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      context.allowsImplicitAnimation = true
      sidebarContainer.animator().frame = sidebarFrame(offscreen: !visible)
      webView.animator().frame.origin.x = visible ? width : 0
      topFadeScrim.animator().frame.origin.x = visible ? width : 0
    }, completionHandler: { [weak self] in
      guard let self else {
        return
      }

      self.contentLeftInset = visible ? width : 0
      self.sidebarContainer.isHidden = !visible
      self.hasUnfinishedAnimations = false
      self.layoutSidebar()
      self.layoutWebView()
      self.layoutPanels()
    })
  }

  func layoutSidebar() {
    sidebarContainer.frame = sidebarFrame(offscreen: !isSidebarVisible)

    let dividerLength = sidebarDivider.length
    sidebarDivider.frame = CGRect(
      x: sidebarContainer.bounds.width - dividerLength,
      y: 0,
      width: dividerLength,
      height: sidebarContainer.bounds.height
    )

    fileTree.frame = sidebarContainer.bounds
    fileTree.topInset = view.safeAreaInsets.top + 8
  }

  /// Puts the toggle button in a real titlebar accessory: it receives clicks
  /// (content-view subviews under the titlebar don't) and shifts the title over.
  func attachSidebarAccessoryIfNeeded() {
    guard let window = view.window else {
      return
    }

    let identifier = NSUserInterfaceItemIdentifier("sidebarToggleAccessory")
    guard !window.titlebarAccessoryViewControllers.contains(where: { $0.identifier == identifier }) else {
      return
    }

    sidebarToggleButton.target = self
    sidebarToggleButton.action = #selector(toggleFileSidebar(_:))
    sidebarToggleButton.frame = CGRect(x: 10, y: 2, width: 24, height: 24)

    let container = NSView(frame: CGRect(x: 0, y: 0, width: 42, height: 28))
    container.addSubview(sidebarToggleButton)

    let accessory = NSTitlebarAccessoryViewController()
    accessory.identifier = identifier
    accessory.view = container
    accessory.layoutAttribute = .leading
    window.addTitlebarAccessoryViewController(accessory)

    // Sort rides in the same titlebar row, right-aligned to the sidebar edge:
    // width = sidebarWidth − traffic lights (~70) − toggle accessory (42)
    sidebarSortButton.target = self
    sidebarSortButton.action = #selector(showSidebarSortMenu(_:))

    let sortWidth = Self.sidebarWidth - 70 - 42
    sidebarSortButton.frame = CGRect(x: sortWidth - 24 - 10, y: 2, width: 24, height: 24)
    sidebarSortButton.isHidden = !isSidebarVisible

    let sortContainer = NSView(frame: CGRect(x: 0, y: 0, width: sortWidth, height: 28))
    sortContainer.addSubview(sidebarSortButton)

    let sortAccessory = NSTitlebarAccessoryViewController()
    sortAccessory.identifier = NSUserInterfaceItemIdentifier("sidebarSortAccessory")
    sortAccessory.view = sortContainer
    sortAccessory.layoutAttribute = .leading
    window.addTitlebarAccessoryViewController(sortAccessory)
  }

  func reloadSidebar() {
    guard isSidebarVisible else {
      return
    }

    setUpSidebarContentIfNeeded()
    fileTree.rootURL = sidebarRootURL
    fileTree.reload()
    fileTree.reveal(document?.fileURL)
  }

  func updateSidebarSelection() {
    guard isSidebarVisible else {
      return
    }

    fileTree.reveal(document?.fileURL)
  }

  func applySidebarSortOrder() {
    fileTree.sortOrder = AppPreferences.Window.sidebarSortOrder
  }
}

// MARK: - Opening files

extension EditorViewController {
  /// Opens the file in this window, replacing the current document. The window
  /// controller is rebound to the new document so the WKWebView never moves.
  func sidebarDidSelectFile(_ url: URL) {
    guard url.standardizedFileURL != document?.fileURL?.standardizedFileURL else {
      return
    }

    if let existing = NSDocumentController.shared.document(for: url) {
      existing.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
      return
    }

    pendingSidebarFileURL = url
    guard let document else {
      return openPendingSidebarFile()
    }

    document.canClose(
      withDelegate: self,
      shouldClose: #selector(document(_:shouldClose:contextInfo:)),
      contextInfo: nil
    )
  }

  @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
    guard shouldClose else {
      pendingSidebarFileURL = nil
      return
    }

    openPendingSidebarFile()
  }

  private func openPendingSidebarFile() {
    guard let url = pendingSidebarFileURL else {
      return
    }

    pendingSidebarFileURL = nil
    let oldDocument = document
    guard let windowController = view.window?.windowController else {
      return
    }

    NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { [weak self] newDocument, _, error in
      guard let self, let newDocument = newDocument as? EditorDocument else {
        if let error {
          NSApp.presentError(error)
        }

        return
      }

      // Detach before close() so closing can't take the window down with it
      oldDocument?.removeWindowController(windowController)
      oldDocument?.close()
      newDocument.addWindowController(windowController)
      newDocument.adoptHostViewController(self)
      self.updateSidebarSelection()

      // The sidebar stays the navigation surface: arrows keep browsing files
      // after a swap instead of the caret jumping into the page
      if self.isSidebarVisible {
        self.fileTree.focus()
      }
    }
  }
}

// MARK: - Private

// Extensions can't add stored properties; the pending URL only exists
// across the canClose save prompt, so a side table is enough.
@MainActor private var pendingSidebarFiles = [ObjectIdentifier: URL]()

private extension EditorViewController {
  var pendingSidebarFileURL: URL? {
    get {
      pendingSidebarFiles[ObjectIdentifier(self)]
    }
    set {
      pendingSidebarFiles[ObjectIdentifier(self)] = newValue
    }
  }

  func sidebarFrame(offscreen: Bool) -> CGRect {
    CGRect(
      x: offscreen ? -Self.sidebarWidth : 0,
      y: 0,
      width: Self.sidebarWidth,
      height: view.bounds.height
    )
  }

  func setUpSidebarContentIfNeeded() {
    guard fileTree.superview == nil else {
      return
    }

    sidebarContainer.addSubview(fileTree)
    fileTree.sortOrder = AppPreferences.Window.sidebarSortOrder
    fileTree.onSelectFile = { [weak self] url in
      self?.sidebarDidSelectFile(url)
    }

    // The divider rides inside the container so it slides along for free
    sidebarDivider.isHidden = false
    sidebarDivider.removeFromSuperview()
    sidebarContainer.addSubview(sidebarDivider)
  }

  func updateSidebarFabOffset(animated: Bool) {
    guard let window = view.window as? EditorWindow, let constraint = window.overlayFabCenterX else {
      return
    }

    let constant = isSidebarVisible ? Self.sidebarWidth / 2 : 0
    (animated ? constraint.animator() : constraint).constant = constant
  }
}

// MARK: - Sort menu

extension EditorViewController {
  @objc func showSidebarSortMenu(_ sender: Any?) {
    let current = AppPreferences.Window.sidebarSortOrder
    let menu = NSMenu()

    let titles: [(FileTreeSortOrder, String)] = [
      (.alphabetical, "Alphabetically"),
      (.created, "Created time"),
      (.modified, "Recency"),
    ]

    for (order, title) in titles {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.state = order == current ? .on : .off
      item.addAction {
        AppPreferences.Window.sidebarSortOrder = order
      }

      menu.addItem(item)
    }

    menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sidebarSortButton.bounds.height + 4), in: sidebarSortButton)
  }
}

// MARK: - QuietIconButton

/**
 Quiet titlebar icon (Claude Code-style placement): dimmed until hovered.
 */
final class QuietIconButton: NSButton {
  private var hoverArea: NSTrackingArea?

  init(symbolName: String, accessibilityLabel: String, pointSize: Double = 14) {
    super.init(frame: .zero)
    isBordered = false
    bezelStyle = .regularSquare
    imagePosition = .imageOnly
    image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?
      .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
    contentTintColor = .secondaryLabelColor
    alphaValue = 0.55
    toolTip = accessibilityLabel
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    // Removing ALL tracking areas kills AppKit's internal tooltip tracking;
    // only replace the one we own
    if let hoverArea {
      removeTrackingArea(hoverArea)
    }

    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInKeyWindow],
      owner: self
    )

    hoverArea = area
    addTrackingArea(area)
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    animator().alphaValue = 1
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    animator().alphaValue = 0.55
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .arrow)
  }
}
