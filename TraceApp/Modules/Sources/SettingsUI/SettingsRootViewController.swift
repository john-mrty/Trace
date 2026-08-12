//
//  SettingsRootViewController.swift
//
//  Created by cyan on 1/26/23.
//

import AppKit
import AppKitExtensions
import SwiftUI

/**
 Root container for settings view, multi-tab based.

 Tabs are switched with a capsule segmented control in a header strip above
 the content. The strip lives in the content view — titlebar accessories
 can't be used here because AppKit hard-clamps bottom accessory heights
 (_heightOfBottomAuxillaryViews) and clips anything taller.
 */
public final class SettingsRootViewController: NSTabViewController {
  static let headerHeight: Double = 58

  private var tabs: [SettingsTabViewController]?
  private var animateChanges = false
  private let tabSelection = SettingsTabSelection()

  public static func withTabs(_ tabs: [SettingsTabViewController]) -> NSWindowController {
    let tabVC = Self()
    tabVC.tabs = tabs

    let containerVC = NSViewController()
    containerVC.view = NSView()
    containerVC.addChild(tabVC)

    let header = NSView()
    let separator = NSBox()
    separator.boxType = .separator

    tabVC.tabSelection.index = 0
    let switcher = SettingsTabSwitcher(
      items: tabs.map { .init(title: $0.title ?? "", icon: $0.icon) },
      onSelect: { [weak tabVC] index in
        tabVC?.selectedTabViewItemIndex = index
      },
      selection: tabVC.tabSelection
    )

    let control = NSHostingView(rootView: switcher)
    containerVC.view.addSubview(header)
    containerVC.view.addSubview(tabVC.view)
    header.addSubview(control)
    header.addSubview(separator)

    [header, separator, control, tabVC.view].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
    }

    NSLayoutConstraint.activate([
      // Nothing else defines the container's width; without this the
      // window's fitting-size pass collapses it
      containerVC.view.widthAnchor.constraint(equalToConstant: 580),

      header.topAnchor.constraint(equalTo: containerVC.view.topAnchor),
      header.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor),
      header.heightAnchor.constraint(equalToConstant: headerHeight),

      control.centerXAnchor.constraint(equalTo: header.centerXAnchor),
      control.centerYAnchor.constraint(equalTo: header.centerYAnchor),

      separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
      separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),

      tabVC.view.topAnchor.constraint(equalTo: header.bottomAnchor),
      tabVC.view.leadingAnchor.constraint(equalTo: containerVC.view.leadingAnchor),
      tabVC.view.trailingAnchor.constraint(equalTo: containerVC.view.trailingAnchor),
      tabVC.view.bottomAnchor.constraint(equalTo: containerVC.view.bottomAnchor),
    ])

    let window = NSPanel(contentViewController: containerVC)
    window.styleMask = [.titled, .closable]
    window.collectionBehavior = .moveToActiveSpace
    window.titlebarSeparatorStyle = .none
    // .none alone doesn't remove the hairline on plain titled windows
    window.titlebarAppearsTransparent = true

    return NSWindowController(window: window)
  }

  override public func viewDidLoad() {
    super.viewDidLoad()
    tabStyle = .unspecified

    tabs?.forEach {
      addTabViewItem($0.tabViewItem)
    }

    (NSCursor.arrow as NSCursorDeprecated).setOnMouseEntered(true)
    view.addTrackingRect(view.bounds, owner: NSCursor.arrow, userData: nil, assumeInside: true)
  }

  override public func viewWillAppear() {
    super.viewWillAppear()
    updateWindowTitle()

    // The initial tab selection fires before the window exists,
    // so its resize was a no-op; apply the size now
    applyWindowSize(animated: false)
  }

  override public func viewDidAppear() {
    super.viewDidAppear()
    view.window?.centerOnScreen()
  }
}

// MARK: - NSTabViewDelegate

extension SettingsRootViewController {
  override public func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    guard let contentVC = tabViewItem?.viewController as? SettingsTabViewController else {
      return
    }

    tabSelection.index = selectedTabViewItemIndex
    updateWindowTitle()

    // Performing in the next run loop has a better visual effect
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
      self.applyWindowSize(animated: self.animateChanges && !self.reduceMotion)

      // Enable animations after initial selection
      self.animateChanges = true
    }

    // Mimic the effect of some 1st-party apps, such as Calendar.app,
    // don't use isHidden, it affects the layout.
    if !reduceMotion {
      view.alphaValue = 0
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        self.view.alphaValue = 1
      }
    }
  }
}

// MARK: - Private

private extension SettingsRootViewController {
  var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  func applyWindowSize(animated: Bool) {
    guard let contentVC = tabViewItems[selectedTabViewItemIndex].viewController as? SettingsTabViewController else {
      return
    }

    view.window?.setFrameSize(CGSize(
      width: 580,
      height: contentVC.contentView.frame.size.height + Self.headerHeight
    ), animated: animated)
  }

  func updateWindowTitle() {
    // With .unspecified tab style the controller no longer syncs the title
    view.window?.title = tabViewItems[selectedTabViewItemIndex].label
  }
}
