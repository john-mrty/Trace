//
//  EditorViewController+GotoLine.swift
//  MarkEditMac
//
//  Created by cyan on 1/17/23.
//

import AppKit
import FontPicker
import SharedUI
import MarkEditKit

extension EditorViewController {
  func showGotoLineWindow(_ sender: Any?) {
    guard let parentRect = view.window?.frame else {
      Logger.assertFail("Failed to retrieve window.frame to proceed")
      return
    }

    if completionContext.isPanelVisible {
      cancelCompletion()
    }

    let window = GotoLineWindow(
      effectViewType: AppDesign.modernEffectView,
      relativeTo: parentRect,
      placeholder: Localized.Document.gotoLineLabel,
      accessibilityHelp: Localized.Document.gotoLineHelp,
      iconName: Icons.arrowUturnBackwardCircle,
      defaultLineNumber: States.selectedLineNumber
    ) { [weak self] lineNumber in
      States.selectedLineNumber = lineNumber
      self?.startTextEditing()
      self?.bridge.selection.gotoLine(lineNumber: lineNumber)
    }

    window.appearance = view.effectiveAppearance
    window.makeKeyAndOrderFront(sender)
  }
}

// MARK: - Private

private extension EditorViewController {
  enum States {
    @MainActor static var selectedLineNumber: Int?
  }
}

// MARK: - Command Palette

extension EditorViewController {
  @IBAction func showCommandPalette(_ sender: Any?) {
    guard let parentRect = view.window?.frame else {
      Logger.assertFail("Failed to retrieve window.frame to proceed")
      return
    }

    if completionContext.isPanelVisible {
      cancelCompletion()
    }

    // Plain material, not NSGlassEffectView: glass draws a rim, the palette wants shadow only
    let window = CommandPaletteWindow(
      effectViewType: NSVisualEffectView.self,
      relativeTo: parentRect,
      placeholder: "Type a command or file name",
      font: AppPreferences.Editor.fontStyle.fontWith(size: AppPreferences.Editor.fontSize),
      caretColor: AppPreferences.Editor.accentColor.nsColor,
      items: Self.commandPaletteItems()
    )

    window.appearance = view.effectiveAppearance
    window.makeKeyAndOrderFront(sender)
  }
}

private extension EditorViewController {
  /// Noise excluded from the palette: system input panels, the palette itself,
  /// and submenus that duplicate better palette sources (recents)
  static let paletteExcludedMenus: Set<String> = [
    "Open Recent", "Services", "Speech", "Substitutions", "Help",
  ]

  static let paletteExcludedSelectors: Set<String> = [
    "showCommandPalette:", "startDictation:", "orderFrontCharacterPalette:", "runToolbarCustomizationPalette:",
  ]

  static func commandPaletteItems() -> [CommandPaletteItem] {
    var items = [CommandPaletteItem]()

    func walk(_ menu: NSMenu, path: String) {
      // Runs validation so toggle items carry their current on/off state
      menu.update()

      for menuItem in menu.items {
        if menuItem.isSeparatorItem || menuItem.isHidden {
          continue
        }

        if let submenu = menuItem.submenu {
          if !paletteExcludedMenus.contains(menuItem.title) {
            walk(submenu, path: path.isEmpty ? menuItem.title : "\(path) › \(menuItem.title)")
          }
          continue
        }

        guard let action = menuItem.action, !menuItem.title.isEmpty,
              !paletteExcludedSelectors.contains(NSStringFromSelector(action)) else {
          continue
        }

        let target = menuItem.target
        items.append(CommandPaletteItem(
          title: menuItem.title,
          subtitle: path,
          shortcut: shortcutDescription(of: menuItem),
          isOn: menuItem.state == .on
        ) {
          _ = NSApp.sendAction(action, to: target, from: menuItem)
        })
      }
    }

    // The app menu is skipped wholesale below; Settings earns its spot back
    // Via the responder chain: the Swift method is fileprivate to AppDelegate
    items.append(CommandPaletteItem(title: "Settings…", subtitle: "Trace", shortcut: "⌘,") {
      _ = NSApp.sendAction(Selector(("showPreferences:")), to: NSApp.appDelegate, from: nil)
    })

    // dropFirst skips the application menu (About, Settings, Hide, Quit…)
    for topItem in NSApp.mainMenu?.items.dropFirst() ?? [] {
      guard let submenu = topItem.submenu, !topItem.isHidden,
            !paletteExcludedMenus.contains(topItem.title) else {
        continue
      }

      walk(submenu, path: topItem.title)
    }

    for url in NSDocumentController.shared.recentDocumentURLs {
      items.append(CommandPaletteItem(
        title: url.lastPathComponent,
        subtitle: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
      ) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
      })
    }

    return items
  }

  static func shortcutDescription(of menuItem: NSMenuItem) -> String {
    let key = menuItem.keyEquivalent
    guard !key.isEmpty else {
      return ""
    }

    var text = ""
    let mask = menuItem.keyEquivalentModifierMask

    if mask.contains(.control) {
      text += "⌃"
    }

    if mask.contains(.option) {
      text += "⌥"
    }

    if mask.contains(.shift) {
      text += "⇧"
    }

    if mask.contains(.command) {
      text += "⌘"
    }

    return text + key.uppercased()
  }
}
