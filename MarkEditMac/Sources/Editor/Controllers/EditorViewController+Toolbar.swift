//
//  EditorViewController+Toolbar.swift
//  MarkEditMac
//
//  Created by cyan on 1/13/23.
//

import AppKit
import MarkEditKit

extension EditorViewController {
  var tableOfContentsMenuButton: NSPopUpButton? {
    view.window?.popUpButton(with: Constants.tableOfContentsMenuIdentifier)
  }

  var statisticsSourceView: NSView? {
    let sourceView = view.window?.titlebarDocumentTitleView
    Logger.assert(sourceView != nil, "Missing source view")
    return sourceView
  }

  private enum Constants {
    static let tableOfContentsMenuIdentifier = NSUserInterfaceItemIdentifier("tableOfContentsMenu")
    static let tableOfContentsMinimumWidth: Double = 160
  }

  func updateToolbarItemMenus(_ menu: NSMenu) {
    if menu.identifier == Constants.tableOfContentsMenuIdentifier {
      updateTableOfContentsMenu(menu)
    }
  }

  func showTableOfContentsMenu(from sourceView: NSView? = nil) {
    bridge.core.handleFocusLost()
    presentedPopover?.close()

    // Anchored to an explicit source view (e.g. the FAB button). Popping up at
    // .zero lets AppKit flip the menu above the anchor near the screen bottom,
    // same as the other FAB menus — manual height offsets drift because
    // menu.size over-reports and the TOC height varies per document.
    if let sourceView {
      let menu = tableOfContentsMenu
      menu.delegate = nil
      Task { @MainActor in
        await populateTableOfContentsMenu(menu)
        menu.popUp(positioning: nil, at: .zero, in: sourceView)
      }
      return
    }

    // Pop up the menu relative to the toolbar item
    if let tableOfContentsMenuButton {
      return RunLoop.main.perform(inModes: [.default, .eventTracking]) {
        tableOfContentsMenuButton.performClick(nil)
      }
    }

    // Pop up the menu relative to the document title view
    if let sourceView = view.window?.titlebarDocumentTitleView {
      tableOfContentsMenu.popUp(
        positioning: nil,
        at: CGPoint(x: sourceView.bounds.minX, y: sourceView.bounds.maxY + 15),
        in: sourceView
      )
    } else {
      Logger.assertFail("Missing document title view")
    }
  }

  @objc func toggleHideSyntaxMarks(_ sender: Any?) {
    AppPreferences.Editor.hideSyntaxMarks.toggle()
  }
}

// MARK: - Private

private extension EditorViewController {
  var tableOfContentsMenu: NSMenu {
    let menu = NSMenu()
    menu.delegate = self
    menu.identifier = Constants.tableOfContentsMenuIdentifier
    menu.minimumWidth = Constants.tableOfContentsMinimumWidth
    // Needed to work around the "Populating a menu window that is already visible" crash
    menu.needsHack = true

    let label = NSMenuItem(title: Localized.Toolbar.tableOfContents, action: nil, keyEquivalent: "")
    label.isEnabled = false

    menu.items = [label, .separator()]
    menu.autoenablesItems = false

    return menu
  }

  func updateTableOfContentsMenu(_ menu: NSMenu) {
    Task {
      await populateTableOfContentsMenu(menu)
    }
  }

  func populateTableOfContentsMenu(_ menu: NSMenu) async {
    // Remove existing items, the first two are placeholders that we want to keep
    for (index, item) in menu.items.enumerated() where index > 1 {
      menu.removeItem(item)
    }

    let tableOfContents = await tableOfContents
    let baseLevel = tableOfContents?.map { $0.level }.min() ?? 1

    tableOfContents?.forEach { info in
      let title = String(repeating: " ", count: (info.level - baseLevel) * 2) + info.title
      let item = menu.addItem(withTitle: title, action: #selector(self.gotoHeader(_:)))
      item.representedObject = info
      item.setAccessibilityLabel(title)
      item.setAccessibilityValue(info.level)

      if info.selected {
        item.setAccessibilityHelp(Localized.General.selected)
      }

      let fontSize = 15.0 - min(3, Double(info.level))
      let attributedTitle = NSMutableAttributedString()

      attributedTitle.append(NSAttributedString(string: info.selected ? "‣" : " ", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
      ]))

      attributedTitle.append(NSAttributedString(string: " \(title)", attributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
      ]))

      item.attributedTitle = attributedTitle
      menu.addItem(.separator())
    }
  }

  @objc func gotoHeader(_ sender: NSMenuItem) {
    guard let headingInfo = sender.representedObject as? HeadingInfo else {
      Logger.assertFail("Failed to get HeadingInfo from sender: \(sender)")
      return
    }

    startTextEditing()
    bridge.toc.gotoHeader(headingInfo: headingInfo)
  }
}
