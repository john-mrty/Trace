//
//  EditorOverlayToolbar.swift
//  MarkEditMac
//
//  Created by cyan on 8/2/26.
//

import AppKit
import AppKitExtensions
import SharedUI

/**
 Floating FAB-style capsule toolbar shown only while `EditorWindow` is in overlay mode,
 where the real `NSToolbar` is hidden. Reuses the app's existing writing actions rather
 than reimplementing them; see `EditorOverlayToolbar.defaultActions(for:)`.
 */
final class EditorOverlayToolbar: NSView {
  struct Action {
    let symbolName: String
    let accessibilityLabel: String
    var currentSymbolName: (() -> String)?
    let handler: (NSButton) -> Void
  }

  private let material = MaterialView()
  private let bezel = BezelView(cornerRadius: Constants.height / 2)
  private let actions: [Action]
  private var buttons: [NSButton] = []

  init(actions: [Action]) {
    self.actions = actions
    super.init(frame: .zero)

    setUpChrome()
    setUpButtons()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: NSSize {
    let buttonsWidth = CGFloat(buttons.count) * Constants.buttonSize
    let spacingWidth = CGFloat(max(0, buttons.count - 1)) * Constants.buttonSpacing
    return NSSize(
      width: Constants.horizontalPadding * 2 + buttonsWidth + spacingWidth,
      height: Constants.height
    )
  }

  override func layout() {
    super.layout()

    material.frame = bounds
    bezel.frame = bounds
    layer?.shadowPath = CGPath(
      roundedRect: bounds,
      cornerWidth: Constants.height / 2,
      cornerHeight: Constants.height / 2,
      transform: nil
    )

    var x = Constants.horizontalPadding
    let y = (bounds.height - Constants.buttonSize) / 2

    for button in buttons {
      button.frame = NSRect(x: x, y: y, width: Constants.buttonSize, height: Constants.buttonSize)
      x += Constants.buttonSize + Constants.buttonSpacing
    }
  }

  func refreshButtonImages() {
    for (index, action) in actions.enumerated() {
      guard let provider = action.currentSymbolName, buttons.indices.contains(index) else {
        continue
      }

      buttons[index].image = .with(
        symbolName: provider(),
        pointSize: Constants.iconPointSize,
        weight: .medium,
        accessibilityLabel: action.accessibilityLabel
      )
    }
  }
}

// MARK: - Private

private extension EditorOverlayToolbar {
  enum Constants {
    static let height: CGFloat = 36
    static let horizontalPadding: CGFloat = 10
    static let buttonSpacing: CGFloat = 2
    static let buttonSize: CGFloat = 28
    static let iconPointSize: Double = 13
  }

  func setUpChrome() {
    wantsLayer = true
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = 0.15
    layer?.shadowRadius = 8
    layer?.shadowOffset = .zero

    material.wantsLayer = true
    material.layer?.cornerCurve = .continuous
    material.layer?.cornerRadius = Constants.height / 2
    material.layer?.masksToBounds = true
    material.material = .popover

    // Reduced transparency gets a solid, fully opaque capsule instead of the blur.
    if AppDesign.reduceTransparency {
      material.tintColor = .windowBackgroundColor
    }

    addSubview(material)
    addSubview(bezel)
  }

  func setUpButtons() {
    buttons = actions.enumerated().map { index, action in
      let button = OverlayIconButton()
      button.image = .with(
        symbolName: action.currentSymbolName?() ?? action.symbolName,
        pointSize: Constants.iconPointSize,
        weight: .medium,
        accessibilityLabel: action.accessibilityLabel
      )
      button.setAccessibilityLabel(action.accessibilityLabel)
      button.toolTip = action.accessibilityLabel
      button.tag = index
      button.target = self
      button.action = #selector(buttonTapped(_:))
      addSubview(button)
      return button
    }
  }

  @objc func buttonTapped(_ sender: NSButton) {
    guard actions.indices.contains(sender.tag) else {
      return
    }

    actions[sender.tag].handler(sender)
  }
}

/// Borderless icon button with a cheap hover highlight via a tracking area.
private final class OverlayIconButton: NSButton {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    isBordered = false
    imagePosition = .imageOnly
    bezelStyle = .regularSquare
    wantsLayer = true
    layer?.cornerCurve = .continuous
    layer?.cornerRadius = 6
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInKeyWindow],
      owner: self
    ))
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    layerBackgroundColor = .quaternaryLabelColor
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    layerBackgroundColor = nil
  }
}
