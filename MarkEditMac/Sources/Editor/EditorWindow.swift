//
//  EditorWindow.swift
//  MarkEditMac
//
//  Created by cyan on 1/12/23.
//

import AppKit
import AppKitExtensions
import MarkEditKit

final class EditorWindow: NSWindow {
  /// True while summoned as the right-edge overlay (Option+`).
  /// Not `private(set)`: the overlay lifecycle lives in `EditorWindow+Overlay.swift`.
  var overlayMode = false
  var savedFrame: NSRect?
  var savedLevel: NSWindow.Level?
  var savedCollectionBehavior: NSWindow.CollectionBehavior?
  var savedToolbarMode: ToolbarMode?
  var isExitingOverlay = false
  var overlayGeneration = 0
  let overlayWidthFraction: CGFloat = 1.0 / 3.0
  let overlayCornerRadius: CGFloat = 12
  var overlayFab: EditorOverlayToolbar?

  /// Forces `.preferred` tabbing for an on-demand window (e.g. "New Tab"),
  /// without mutating the persisted `AppPreferences.Window.tabbingMode`.
  @MainActor static var forcedTabbing = false

  var toolbarMode: ToolbarMode? {
    didSet {
      toolbarStyle = toolbarMode == .compact ? .unifiedCompact : .unified
      super.toolbar = toolbarMode == .hidden ? nil : cachedToolbar
      updateTitleBarAppearance()
      (contentViewController as? EditorViewController)?.updateHideSyntaxMarksToolbarIcon()
    }
  }

  var reduceTransparency: Bool? {
    didSet {
      updateTitleBarAppearance()
    }
  }

  var prefersTintedToolbar: Bool = false {
    didSet {
      updateTitleBarAppearance()
    }
  }

  override var toolbar: NSToolbar? {
    get {
      super.toolbar
    }
    set {
      cachedToolbar = newValue
      super.toolbar = toolbarMode == .hidden ? nil : newValue
    }
  }

  private var cachedToolbar: NSToolbar?
  private weak var cachedTitlebarBackgroundView: NSView?
  private weak var cachedTitlebarDecorationView: NSView?

  override func awakeFromNib() {
    super.awakeFromNib()
    toolbar = NSToolbar() // Required for multi-tab layout
    // Fork behavior: the FAB replaces the toolbar everywhere, ignore the toolbar-mode pref
    toolbarMode = .hidden
    tabbingMode = Self.forcedTabbing ? .preferred : AppPreferences.Window.tabbingMode
    reduceTransparency = AppDesign.reduceTransparency

    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil
    )
  }

  @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
    updateTitleBarAppearance()
    (contentViewController as? EditorViewController)?.updateWindowColors(.current)
  }

  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    updateTitleBarAppearance(clearCaches: false)
  }

  /// Applies all custom title-bar tweaks derived from current state:
  /// `(isFullscreen, toolbarMode, reduceTransparency, prefersTintedToolbar)`.
  /// Safe to call repeatedly; also runs implicitly after each layout pass.
  func updateTitleBarAppearance(clearCaches: Bool = true) {
    if clearCaches {
      cachedTitlebarBackgroundView = nil
      cachedTitlebarDecorationView = nil
    }

    // The titlebar background view also backs the auto-hiding titlebar overlay in
    // fullscreen. When the toolbar is hidden, nothing else backs it, so keep
    // the effect view visible and fully opaque in that specific case to avoid
    // a transparent overlay.
    if cachedTitlebarBackgroundView == nil {
      cachedTitlebarBackgroundView = titlebarBackgroundView
    }

    if let view = cachedTitlebarBackgroundView {
      let needsOverlay = styleMask.contains(.fullScreen) && toolbarMode == .hidden
      view.alphaValue = needsOverlay ? 1 : (prefersTintedToolbar ? 0.3 : 0.7)
      view.isHidden = !needsOverlay && (AppDesign.reduceTransparency || AppDesign.modernTitleBar)

      // Blend the color of contents behind the window
      (view as? NSVisualEffectView)?.blendingMode = .behindWindow
    } else {
      Logger.assertFail("Missing cachedTitlebarBackgroundView")
    }

    if AppDesign.modernTitleBar {
      if cachedTitlebarDecorationView == nil {
        cachedTitlebarDecorationView = titlebarDecorationView
      }

      // Disable the separator instead of using `titlebarAppearsTransparent`,
      // which breaks "Merge All Windows".
      if let view = cachedTitlebarDecorationView {
        let selector = sel_getUid("setDrawsBottomSeparator:")
        if view.responds(to: selector) {
          unsafeBitCast(
            view.method(for: selector),
            to: (@convention(c) (NSView, Selector, Bool) -> Void).self
          )(view, selector, false)
        } else {
          Logger.assertFail("Missing setDrawsBottomSeparator: in _NSTitlebarDecorationView")
          view.isHidden = true
        }
      } else {
        Logger.assertFail("Missing cachedTitlebarDecorationView")
      }
    }

    // Deliberately dim the icon to get on well with tinted style
    titlebarDocumentButton?.alphaValue = prefersTintedToolbar ? 0.8 : 1.0
  }

  override func close() {
    // Unconditional: tears down the FAB's NSEvent monitor for non-overlay windows too
    hideOverlayFab()
    resetOverlayStateBeforeClosing()
    super.close()
  }

  /// AppKit auto-joins tab groups here (e.g. opening another document while this window
  /// is key). The overlay frame/chrome must not end up hosting a second window's toolbar,
  /// so exit overlay on both sides of the join before letting the join happen.
  override func addTabbedWindow(_ window: NSWindow, ordered: NSWindow.OrderingMode) {
    exitOverlayForTabJoin()
    (window as? EditorWindow)?.exitOverlayForTabJoin()
    super.addTabbedWindow(window, ordered: ordered)
  }

  override func resignKey() {
    super.resignKey()

    if overlayMode {
      exitOverlayMode(animated: true)
    }
  }

  /// Exits overlay mode if currently active; no-op otherwise. Shared entry point for
  /// both this window's own `cancelOperation` and `EditorViewController`'s Esc handling,
  /// since the view controller is earlier in the responder chain and doesn't forward.
  func dismissOverlayIfNeeded() {
    if overlayMode {
      exitOverlayMode(animated: true)
    }
  }

  override func cancelOperation(_ sender: Any?) {
    guard overlayMode else {
      super.cancelOperation(sender)
      return
    }

    dismissOverlayIfNeeded()
  }
}
