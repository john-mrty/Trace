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
  private(set) var overlayMode = false
  private var savedFrame: NSRect?
  private var savedLevel: NSWindow.Level?
  private var savedCollectionBehavior: NSWindow.CollectionBehavior?
  private var isExitingOverlay = false
  private var overlayGeneration = 0
  private let overlayWidthFraction: CGFloat = 1.0 / 3.0

  /// Forces `.preferred` tabbing for an on-demand window (e.g. "New Tab"),
  /// without mutating the persisted `AppPreferences.Window.tabbingMode`.
  @MainActor static var forcedTabbing = false

  var toolbarMode: ToolbarMode? {
    didSet {
      toolbarStyle = toolbarMode == .compact ? .unifiedCompact : .unified
      super.toolbar = toolbarMode == .hidden ? nil : cachedToolbar
      updateTitleBarAppearance()
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
    toolbarMode = AppPreferences.Window.toolbarMode
    tabbingMode = Self.forcedTabbing ? .preferred : AppPreferences.Window.tabbingMode
    reduceTransparency = AppDesign.reduceTransparency

    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.updateTitleBarAppearance()
      (self?.contentViewController as? EditorViewController)?.updateWindowColors(.current)
    }
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

  /// Summons this window as a right-edge overlay: floating above other apps, full height.
  /// Full-screen windows are out of scope for v1; falls back to a plain key/front.
  func enterOverlayMode(animated: Bool) {
    guard !overlayMode else {
      return
    }

    guard !styleMask.contains(.fullScreen), let visible = (screen ?? NSScreen.main)?.visibleFrame else {
      makeKeyAndOrderFront(nil)
      return
    }

    // A fast re-summon can land mid slide-out; finalize that exit synchronously
    // first so `frame` below reflects the real pre-overlay geometry, not a
    // mid-animation one, and so the stale animation completion is neutralized.
    finalizeExitingOverlayIfNeeded()

    overlayMode = true
    isExitingOverlay = false
    savedFrame = frame
    savedLevel = level
    savedCollectionBehavior = collectionBehavior

    level = .floating
    collectionBehavior.insert(.canJoinAllSpaces)
    collectionBehavior.insert(.fullScreenAuxiliary)

    let target = EditorOverlayGeometry.frame(in: visible, widthFraction: overlayWidthFraction)
    if animated && !AppDesign.reduceMotion {
      setFrame(EditorOverlayGeometry.offscreenFrame(in: visible, widthFraction: overlayWidthFraction), display: false)
      makeKeyAndOrderFront(nil)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.18
        animator().setFrame(target, display: true)
      }
    } else {
      setFrame(target, display: true)
      makeKeyAndOrderFront(nil)
    }
  }

  /// Dismisses the overlay, restoring the window's pre-overlay frame/level/behavior.
  /// `completion` runs once the window has finished ordering out, so callers (e.g. hiding
  /// the app) don't cut the slide-out animation short.
  func exitOverlayMode(animated: Bool, completion: (() -> Void)? = nil) {
    guard overlayMode, !isExitingOverlay else {
      completion?()
      return
    }

    isExitingOverlay = true
    overlayMode = false
    overlayGeneration += 1
    let generation = overlayGeneration

    if let savedLevel {
      level = savedLevel
    }

    if let savedCollectionBehavior {
      collectionBehavior = savedCollectionBehavior
    }

    let restore = { [weak self] in
      guard let self, self.overlayGeneration == generation else {
        // A newer enter/exit cycle already finalized or superseded this one.
        return
      }

      if let savedFrame = self.savedFrame {
        self.setFrame(savedFrame, display: true)
      }

      self.orderOut(nil)
      self.isExitingOverlay = false
      completion?()
    }

    if animated && !AppDesign.reduceMotion, let visible = (screen ?? NSScreen.main)?.visibleFrame {
      let off = EditorOverlayGeometry.offscreenFrame(in: visible, widthFraction: overlayWidthFraction)
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.16
        animator().setFrame(off, display: true)
      }, completionHandler: restore)
    } else {
      restore()
    }
  }

  /// Synchronously finishes an in-flight `exitOverlayMode` animation, restoring the
  /// pre-overlay frame without animating and without ordering the window out.
  /// Bumps `overlayGeneration` so the original animation's completion becomes a no-op.
  private func finalizeExitingOverlayIfNeeded() {
    guard isExitingOverlay else {
      return
    }

    if let savedFrame {
      setFrame(savedFrame, display: false)
    }

    isExitingOverlay = false
    overlayGeneration += 1
  }

  /// Restores overlay-related window state (level, collection behavior, frame) without
  /// animation and clears overlay flags. Used when the window is about to close, so
  /// none of the floating-overlay state persists into a restored window next launch.
  private func resetOverlayStateBeforeClosing() {
    guard overlayMode || isExitingOverlay else {
      return
    }

    if let savedLevel {
      level = savedLevel
    }

    if let savedCollectionBehavior {
      collectionBehavior = savedCollectionBehavior
    }

    if let savedFrame {
      setFrame(savedFrame, display: false)
    }

    overlayMode = false
    isExitingOverlay = false
    overlayGeneration += 1
  }

  override func close() {
    resetOverlayStateBeforeClosing()
    super.close()
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
