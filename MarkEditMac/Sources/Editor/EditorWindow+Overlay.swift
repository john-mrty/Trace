//
//  EditorWindow+Overlay.swift
//  MarkEditMac
//
//  Created by cyan on 8/2/26.
//

import AppKit
import AppKitExtensions
import MarkEditKit

/**
 Overlay lifecycle for `EditorWindow` (Option+` right-edge overlay), plus the floating FAB
 toolbar (`EditorOverlayToolbar`) shown while in that mode. Lives in its own file so the
 main `EditorWindow` class body stays under SwiftLint's `type_body_length` limit. The FAB
 reuses the same selectors/menus as the real `NSToolbar` items in
 `EditorViewController+Toolbar.swift`, in the same order as `.defaultItems`.
 */
extension EditorWindow {
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
    savedToolbarMode = toolbarMode

    level = .floating
    collectionBehavior.insert(.canJoinAllSpaces)
    collectionBehavior.insert(.fullScreenAuxiliary)
    toolbarMode = .hidden
    applyOverlayChrome()
    showOverlayFab()

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

      if let savedToolbarMode = self.savedToolbarMode {
        self.toolbarMode = savedToolbarMode
      }

      self.resetOverlayChrome()
      self.hideOverlayFab()
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
  func finalizeExitingOverlayIfNeeded() {
    guard isExitingOverlay else {
      return
    }

    if let savedFrame {
      setFrame(savedFrame, display: false)
    }

    if let savedToolbarMode {
      toolbarMode = savedToolbarMode
    }

    resetOverlayChrome()
    hideOverlayFab()
    isExitingOverlay = false
    overlayGeneration += 1
  }

  /// Restores overlay-related window state (level, collection behavior, frame) without
  /// animation and clears overlay flags. Used when the window is about to close, so
  /// none of the floating-overlay state persists into a restored window next launch.
  func resetOverlayStateBeforeClosing() {
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

    if let savedToolbarMode {
      toolbarMode = savedToolbarMode
    }

    resetOverlayChrome()
    hideOverlayFab()
    overlayMode = false
    isExitingOverlay = false
    overlayGeneration += 1
  }

  /// Gives the overlay a floating-panel look: rounded corners + a hairline border.
  /// Paired with `resetOverlayChrome()`, called from every exit path.
  func applyOverlayChrome() {
    guard let view = contentView else {
      return
    }

    view.wantsLayer = true

    guard let layer = view.layer else {
      return
    }

    layer.cornerRadius = overlayCornerRadius
    layer.masksToBounds = true
    layer.borderWidth = 1
    layer.borderColor = NSColor.separatorColor.cgColor
  }

  func resetOverlayChrome() {
    guard let layer = contentView?.layer else {
      return
    }

    layer.cornerRadius = 0
    layer.masksToBounds = false
    layer.borderWidth = 0
    layer.borderColor = nil
  }

  func showOverlayFab() {
    guard overlayFab == nil,
          let contentView,
          let editorViewController = contentViewController as? EditorViewController else {
      return
    }

    let fab = EditorOverlayToolbar(actions: overlayFabActions(for: editorViewController))
    fab.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(fab)

    NSLayoutConstraint.activate([
      fab.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      fab.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: Constants.fabTopOffset),
    ])

    overlayFab = fab
  }

  func hideOverlayFab() {
    overlayFab?.removeFromSuperview()
    overlayFab = nil
  }
}

// MARK: - Private

private extension EditorWindow {
  enum Constants {
    static let fabTopOffset: CGFloat = 12
  }

  /// The 5 most useful writing actions, matching `NSToolbarItem.Identifier.defaultItems`'s
  /// order: table of contents, headers, bold, italic, list.
  func overlayFabActions(for viewController: EditorViewController) -> [EditorOverlayToolbar.Action] {
    [
      EditorOverlayToolbar.Action(
        symbolName: Icons.listBulletRectangle,
        accessibilityLabel: Localized.Toolbar.tableOfContents
      ) { [weak viewController] _ in
        viewController?.showTableOfContentsMenu()
      },
      EditorOverlayToolbar.Action(
        symbolName: Icons.numberSign,
        accessibilityLabel: Localized.Toolbar.formatHeaders
      ) { button in
        NSApp.appDelegate?.formatHeadersMenu?.copiedMenu?.popUp(positioning: nil, at: .zero, in: button)
      },
      EditorOverlayToolbar.Action(
        symbolName: Icons.bold,
        accessibilityLabel: Localized.Toolbar.toggleBold
      ) { [weak viewController] _ in
        viewController?.toggleBold(nil)
      },
      EditorOverlayToolbar.Action(
        symbolName: Icons.italic,
        accessibilityLabel: Localized.Toolbar.toggleItalic
      ) { [weak viewController] _ in
        viewController?.toggleItalic(nil)
      },
      EditorOverlayToolbar.Action(
        symbolName: Icons.listBullet,
        accessibilityLabel: Localized.Toolbar.toggleList
      ) { button in
        let menu = NSMenu()
        menu.items = [
          NSApp.appDelegate?.formatBulletItem,
          NSApp.appDelegate?.formatNumberingItem,
          NSApp.appDelegate?.formatTodoItem,
        ].compactMap { $0?.copiedItem }
        menu.popUp(positioning: nil, at: .zero, in: button)
      },
    ]
  }
}
