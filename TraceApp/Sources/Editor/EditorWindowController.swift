//
//  EditorWindowController.swift
//  MarkEditMac
//
//  Created by cyan on 12/12/22.
//

import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate {
  var autosavedFrame: CGRect?
  var needsUpdateFocus = false

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    shouldCascadeWindows = true
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    window?.backgroundColor = .controlBackgroundColor

    windowFrameAutosaveName = "Editor"
    window?.setFrameUsingName(windowFrameAutosaveName)
    saveWindowRect()

    // Fork behavior: the FAB is the toolbar in every window, not just the overlay
    (window as? EditorWindow)?.showOverlayFab()
  }

  override func showWindow(_ sender: Any?) {
    if shouldWaitResetting {
      // Snapshot the caller's tabbing preference,
      // it may be reset before our deferred super call.
      let callerTabbingPreference = NSWindow.allowsAutomaticWindowTabbing

      Task { @MainActor [weak self] in
        guard let self else {
          return
        }

        // Defer the actual show until the editor finishes its first paint
        await self.editorViewController?.waitUntilEditorReset()

        let tabbingToRestore = NSWindow.allowsAutomaticWindowTabbing
        NSWindow.allowsAutomaticWindowTabbing = callerTabbingPreference

        self.showWindowImmediately(sender)
        NSWindow.allowsAutomaticWindowTabbing = tabbingToRestore
      }

      return
    }

    showWindowImmediately(sender)
  }

  func windowDidBecomeMain(_ notification: Notification) {
    NSApplication.shared.closeOpenPanels()
  }

  func windowDidResignMain(_ notification: Notification) {
    if !AppPreferences.Editor.hideSyntaxMarks {
      // In theory, this is not indeed, but we've seen wrong state without this
      editorViewController?.bridge.core.handleMouseExited(clientX: 0, clientY: 0)
    }
  }

  func windowDidBecomeKey(_ notification: Notification) {
    // The preloaded content view controller attaches after windowDidLoad,
    // so ensure the always-on FAB here; no-op once it exists.
    (window as? EditorWindow)?.showOverlayFab()

    if needsUpdateFocus {
      editorViewController?.refreshEditFocus()
      needsUpdateFocus = false
    }

    // The shared "field editor" tends to hold focus,
    // manually resign the focus to ensure cmd-f responds correctly.
    for editor in EditorPreloader.shared.viewControllers() where editor !== editorViewController {
      editor.resignFindPanelFocus()
    }

    // The main menu is a singleton, we need to update the menu items for the active editor
    editorViewController?.resetUserDefinedMenuItems()

    // Try if warmup can fix the empty suggestion bug
    NSSpellChecker.warmUp
  }

  func windowDidResignKey(_ notification: Notification) {
    needsUpdateFocus = editorViewController?.webView.isFirstResponder == true
    editorViewController?.cancelCompletion()
    editorViewController?.bridge.core.handleFocusLost()
  }

  func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
    // By default, zooming a window doesn't clear the tiling state,
    // this is different from moving or resizing the window.
    //
    // We manually clear the tiling state after a short delay to keep the behavior consistent.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let autosaveName = self?.windowFrameAutosaveName else {
        return
      }

      UserDefaults.resetTilingState(for: "NSWindow Frame \(autosaveName)")
    }

    return true
  }

  func windowDidResize(_ notification: Notification) {
    window?.saveFrame(usingName: windowFrameAutosaveName)
    editorViewController?.cancelCompletion()
  }

  // Capture tab state here, not in windowWillClose. By that point the window
  // is already removed from the tab group so tabbedWindows is nil.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    captureTabIndex(for: sender)
    return true
  }

  // Refresh titlebar appearance after fullscreen transitions,
  // when the final `.fullScreen` style mask bit is available.
  func windowDidEnterFullScreen(_ notification: Notification) {
    updateTitleBarAppearance()
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    updateTitleBarAppearance()
  }
}

// MARK: - Private

private extension EditorWindowController {
  var editorViewController: EditorViewController? {
    contentViewController as? EditorViewController
  }

  var shouldWaitResetting: Bool {
    guard let editor = editorViewController else {
      return false
    }

    return editor.hasFinishedLoading && editor.pendingResetCount > 0
  }

  func showWindowImmediately(_ sender: Any?) {
    // Gentle scale + fade on first show; the overlay has its own slide-in
    let animatable = window?.isVisible == false
      && !AppDesign.reduceMotion
      && (window as? EditorWindow)?.overlayMode == false

    if animatable {
      window?.alphaValue = 0
    }

    super.showWindow(sender)

    guard animatable, let window else {
      window?.alphaValue = 1
      return
    }

    let target = window.frame
    window.setFrame(target.insetBy(dx: target.width * 0.01, dy: target.height * 0.01), display: false)

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      window.animator().alphaValue = 1
      window.animator().setFrame(target, display: true)
    }
  }

  func updateTitleBarAppearance() {
    (window as? EditorWindow)?.updateTitleBarAppearance()
    editorViewController?.updateWindowColors(.current)
  }

  func captureTabIndex(for window: NSWindow) {
    let document = editorViewController?.document
    let tabbedWindows = window.tabbedWindows
    let tabIndex = tabbedWindows?.firstIndex(of: window)
    let sibling = tabbedWindows?.first { $0 !== window }

    // tabbedWindows is nil for truly standalone windows, but a lone tab
    // broken out of a group reports tabbedWindows.count == 1. Treat both as standalone.
    let isStandalone = tabbedWindows == nil || tabbedWindows?.count == 1

    document?.lastTabIndex = tabIndex
    document?.lastWasStandalone = isStandalone
    document?.lastSiblingWindow = sibling
  }

  func saveWindowRect() {
  #if DEBUG
    guard ProcessInfo.processInfo.environment["DEBUG_TAKING_SCREENSHOTS"] != "YES" else {
      return
    }
  #endif

    // Editor view controllers are created without having a window (for pre-loading),
    // this is used for restoring the autosaved window frame.
    //
    // Unfortunately, we need to manually do the window cascading.
    //
    // Cascade from the frontmost existing EditorWindow's frame, not the new window's
    // autosaved frame, to ensure the visual offset is relative to what the user sees.
    let existingWindow = NSApp.orderedWindows.first {
      $0 is EditorWindow && $0 !== window
    }

    if let window, let sourceFrame = existingWindow?.frame {
      autosavedFrame = window.cascadeRect(from: sourceFrame)
    } else {
      autosavedFrame = window?.frame
    }
  }
}
