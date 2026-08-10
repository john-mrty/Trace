//
//  EditorViewController+GotoLine.swift
//  MarkEditMac
//
//  Created by cyan on 1/17/23.
//

import AppKit
import SwiftUI
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

// MARK: - Quick Open

extension EditorViewController {
  @IBAction func showQuickOpen(_ sender: Any?) {
    guard let parentRect = view.window?.frame else {
      Logger.assertFail("Failed to retrieve window.frame to proceed")
      return
    }

    if completionContext.isPanelVisible {
      cancelCompletion()
    }

    let window = CommandPaletteWindow(
      effectViewType: NSVisualEffectView.self,
      relativeTo: parentRect,
      placeholder: "Open a file…",
      font: AppPreferences.Editor.fontStyle.fontWith(size: AppPreferences.Editor.fontSize),
      caretColor: AppPreferences.Editor.accentColor.nsColor,
      items: quickOpenItems()
    )

    window.appearance = view.effectiveAppearance
    window.makeKeyAndOrderFront(sender)
  }
}

extension EditorViewController {
  // Shared with the sidebar's file tree
  static let quickOpenExtensions: Set<String> = ["md", "markdown", "mdown", "txt", "text"]
}

private extension EditorViewController {

  func quickOpenItems() -> [CommandPaletteItem] {
    var urls = [URL]()
    var seen = Set<String>()
    let currentPath = document?.fileURL?.standardizedFileURL.path
    let root = document?.fileURL?.deletingLastPathComponent()

    func append(_ url: URL) {
      let path = url.standardizedFileURL.path
      if path != currentPath && seen.insert(path).inserted {
        urls.append(url)
      }
    }

    NSDocumentController.shared.recentDocumentURLs.forEach(append)
    (root.map(Self.markdownFiles(in:)) ?? []).forEach(append)

    return urls.map { url in
      let folder = url.deletingLastPathComponent().path
      let subtitle: String
      if let rootPath = root?.path, folder.hasPrefix(rootPath) {
        subtitle = String(folder.dropFirst(rootPath.count).drop { $0 == "/" })
      } else {
        subtitle = (folder as NSString).abbreviatingWithTildeInPath
      }

      return CommandPaletteItem(title: url.lastPathComponent, subtitle: subtitle) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
      }
    }
  }

  /// Recursively collects Markdown-ish files under root, most recently modified first.
  /// Capped so a palette opened from a huge folder stays instant.
  static func markdownFiles(in root: URL) -> [URL] {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return []
    }

    var found = [(url: URL, date: Date)]()
    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: keys)
      if values?.isDirectory == true {
        if url.lastPathComponent == "node_modules" {
          enumerator.skipDescendants()
        }
        continue
      }

      guard quickOpenExtensions.contains(url.pathExtension.lowercased()) else {
        continue
      }

      found.append((url, values?.contentModificationDate ?? .distantPast))
      if found.count >= 500 {
        break
      }
    }

    return found.sorted { $0.date > $1.date }.map { $0.url }
  }
}

// MARK: - Command Palette Items

private extension EditorViewController {
  /// Noise excluded from the palette: system input panels, the palette itself,
  /// and submenus that duplicate better palette sources (recents)
  static let paletteExcludedMenus: Set<String> = [
    "Open Recent", "Open In…", "Reopen with Encoding", "Line Endings", "Purge History Versions",
    "Services", "Speech", "Substitutions", "Window", "Help",
  ]

  static let paletteExcludedSelectors: Set<String> = [
    "showCommandPalette:", "startDictation:", "orderFrontCharacterPalette:", "runToolbarCustomizationPalette:",
    "grantFolderAccess:",
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
      _ = NSApp.sendAction(NSSelectorFromString("showPreferences:"), to: NSApp.appDelegate, from: nil)
    })

    let appearances: [(Appearance, String)] = [(.system, "System"), (.light, "Light"), (.dark, "Dark")]
    for (appearance, name) in appearances {
      items.append(CommandPaletteItem(
        title: "Appearance: \(name)",
        subtitle: "View",
        isOn: AppPreferences.General.appearance == appearance
      ) {
        NSApp.appearance = appearance.resolved()
        AppPreferences.General.appearance = appearance
      })
    }

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

    guard let glyph = keyGlyph(for: key) else {
      return ""
    }

    return text + glyph
  }

  /// Arrow/function key equivalents are private-use characters that render as
  /// empty boxes; map the common ones and hide anything else unmappable
  static let specialKeyGlyphs: [UInt32: String] = [
    UInt32(NSUpArrowFunctionKey): "↑",
    UInt32(NSDownArrowFunctionKey): "↓",
    UInt32(NSLeftArrowFunctionKey): "←",
    UInt32(NSRightArrowFunctionKey): "→",
    UInt32(NSHomeFunctionKey): "↖",
    UInt32(NSEndFunctionKey): "↘",
    UInt32(NSPageUpFunctionKey): "⇞",
    UInt32(NSPageDownFunctionKey): "⇟",
    UInt32(NSDeleteFunctionKey): "⌦",
    0x08: "⌫", 0x7F: "⌫",
    0x0D: "↩", 0x0A: "↩",
    0x09: "⇥", 0x1B: "⎋", 0x20: "Space",
  ]

  static func keyGlyph(for key: String) -> String? {
    guard key.count == 1, let scalar = key.unicodeScalars.first else {
      return key.uppercased()
    }

    if let glyph = specialKeyGlyphs[scalar.value] {
      return glyph
    }

    return (0xF700...0xF8FF).contains(scalar.value) ? nil : key.uppercased()
  }
}

// MARK: - Keyboard Shortcuts

extension EditorViewController {
  @objc func showKeyboardShortcuts(_ sender: Any?) {
    guard presentedViewControllers?.contains(where: { $0 is NSHostingController<KeyboardShortcutsView> }) != true else {
      return
    }

    final class Box { weak var controller: NSViewController? }
    let box = Box()

    let rootView = KeyboardShortcutsView(groups: Self.shortcutGroups()) { [weak self] in
      if let controller = box.controller {
        self?.dismiss(controller)
      }
    }

    let controller = NSHostingController(rootView: rootView)
    box.controller = controller
    presentAsSheet(controller)
  }
}

private extension EditorViewController {
  static func shortcutGroups() -> [ShortcutGroup] {
    var groups = [ShortcutGroup]()

    // dropFirst skips the application menu (About, Hide, Quit…)
    for topItem in NSApp.mainMenu?.items.dropFirst() ?? [] {
      guard let submenu = topItem.submenu, !topItem.isHidden else {
        continue
      }

      var rows = [ShortcutGroup.Row]()
      func walk(_ menu: NSMenu) {
        for item in menu.items {
          if let sub = item.submenu {
            walk(sub)
            continue
          }

          let shortcut = shortcutDescription(of: item)
          if !shortcut.isEmpty, !item.title.isEmpty, !item.isHidden {
            rows.append(ShortcutGroup.Row(title: item.title, shortcut: shortcut))
          }
        }
      }

      walk(submenu)
      if !rows.isEmpty {
        groups.append(ShortcutGroup(title: topItem.title, rows: rows))
      }
    }

    return groups
  }
}

struct ShortcutGroup {
  struct Row: Hashable {
    let title: String
    let shortcut: String
  }

  let title: String
  let rows: [Row]
}

struct KeyboardShortcutsView: View {
  let groups: [ShortcutGroup]
  let dismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Keyboard Shortcuts")
          .font(.headline)

        Spacer()
        Button("Done", action: dismiss)
          .keyboardShortcut(.cancelAction)
      }
      .padding(16)

      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          ForEach(groups, id: \.title) { group in
            VStack(alignment: .leading, spacing: 4) {
              Text(group.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

              ForEach(group.rows, id: \.self) { row in
                HStack {
                  Text(row.title)
                  Spacer()
                  Text(row.shortcut)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
              }
            }
          }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(width: 400, height: 480)
  }
}
