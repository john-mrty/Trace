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
      items: Self.commandPaletteItems()
    )

    window.appearance = view.effectiveAppearance
    window.makeKeyAndOrderFront(sender)
  }
}

private extension EditorViewController {
  static func commandPaletteItems() -> [CommandPaletteItem] {
    var items = [CommandPaletteItem]()

    func walk(_ menu: NSMenu, path: String) {
      for menuItem in menu.items {
        if menuItem.isSeparatorItem || menuItem.isHidden {
          continue
        }

        if let submenu = menuItem.submenu {
          walk(submenu, path: path.isEmpty ? menuItem.title : "\(path) › \(menuItem.title)")
          continue
        }

        guard let action = menuItem.action, !menuItem.title.isEmpty else {
          continue
        }

        guard action != #selector(Self.showCommandPalette(_:)),
              NSStringFromSelector(action) != "showAboutPanel:" else {
          continue
        }

        let target = menuItem.target
        items.append(CommandPaletteItem(
          title: menuItem.title,
          subtitle: path,
          shortcut: shortcutDescription(of: menuItem)
        ) {
          _ = NSApp.sendAction(action, to: target, from: menuItem)
        })
      }
    }

    if let mainMenu = NSApp.mainMenu {
      walk(mainMenu, path: "")
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
