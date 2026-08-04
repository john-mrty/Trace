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
    var symbolName: String?
    let accessibilityLabel: String
    var currentSymbolName: (() -> String)?
    // For glyphs SF Symbols lacks; takes precedence over symbolName
    var customImage: NSImage?
    // When true, the icon tints with the app accent color
    var isActive: (() -> Bool)?
    let handler: (NSButton) -> Void
  }

  private let background = MaterialView()
  private let bezel = BezelView(cornerRadius: Constants.height / 2)
  private let actions: [Action]
  private var buttons: [NSButton] = []
  private var scrollMonitor: Any?
  private var settleWorkItem: DispatchWorkItem?

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

  // Install the scroll monitor only while attached to a window; this also
  // tears it down on removal, avoiding main-actor work in deinit.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    if window == nil {
      if let scrollMonitor {
        NSEvent.removeMonitor(scrollMonitor)
        self.scrollMonitor = nil
      }

      settleWorkItem?.cancel()
    } else if scrollMonitor == nil {
      // mouseMoved events need opting in; used to un-dim after typing
      window?.acceptsMouseMovedEvents = true
      setUpEventMonitor()
    }
  }

  override func layout() {
    super.layout()

    background.frame = bounds
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

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyTint()
  }

  func refreshButtonImages() {
    for (index, action) in actions.enumerated() where buttons.indices.contains(index) {
      let button = buttons[index]

      if let isActive = action.isActive {
        button.contentTintColor = isActive() ? AppPreferences.Editor.accentColor.nsColor : nil
      }

      guard let provider = action.currentSymbolName else {
        continue
      }

      if !AppDesign.reduceMotion {
        let transition = CATransition()
        transition.duration = 0.18
        transition.type = .fade
        button.layer?.add(transition, forKey: "imageFade")
      }

      button.image = .with(
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
    static let restingShadowRadius: CGFloat = 8
    static let raisedShadowRadius: CGFloat = 18
    static let restingShadowOpacity: Float = 0.18
    static let raisedShadowOpacity: Float = 0.32
    static let shadowSettleDelay: TimeInterval = 0.3
  }

  func setUpChrome() {
    wantsLayer = true
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = Constants.restingShadowOpacity
    layer?.shadowRadius = Constants.restingShadowRadius
    layer?.shadowOffset = CGSize(width: 0, height: -1)

    background.wantsLayer = true
    background.layer?.cornerCurve = .continuous
    background.layer?.cornerRadius = Constants.height / 2
    background.layer?.masksToBounds = true

    // Same recipe as the document background: backdrop blur + near-opaque tint
    background.material = .popover
    applyTint()

    addSubview(background)
    addSubview(bezel)
  }

  // Layer colors don't track appearance changes, so resolve manually
  func applyTint() {
    let base: NSColor = effectiveAppearance.isDarkMode ? NSColor(white: 0.16, alpha: 1) : .white
    background.tintColor = base.withAlphaComponent(0.95)
  }

  func setUpEventMonitor() {
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .mouseMoved]) { [weak self] event in
      MainActor.assumeIsolated {
        self?.handleMonitoredEvent(event)
      }
      return event
    }
  }

  func handleMonitoredEvent(_ event: NSEvent) {
    guard event.window === window else {
      return
    }

    switch event.type {
    case .keyDown:
      // Recede while writing; any pointer activity brings it back
      setDimmed(true)
    case .mouseMoved:
      setDimmed(false)
    case .scrollWheel:
      setDimmed(false)
      scrollDidOccur()
    default:
      break
    }
  }

  func setDimmed(_ dimmed: Bool) {
    let target: CGFloat = dimmed ? 0.4 : 1
    guard alphaValue != target else {
      return
    }

    if AppDesign.reduceMotion {
      alphaValue = target
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        animator().alphaValue = target
      }
    }
  }

  func scrollDidOccur() {
    guard !AppDesign.reduceMotion else {
      return
    }

    setShadow(raised: true)
    settleWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.setShadow(raised: false)
    }

    settleWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.shadowSettleDelay, execute: workItem)
  }

  /// Backing layers suppress implicit animations, so animate the shadow explicitly.
  func setShadow(raised: Bool) {
    guard let layer else {
      return
    }

    let radius = raised ? Constants.raisedShadowRadius : Constants.restingShadowRadius
    let opacity = raised ? Constants.raisedShadowOpacity : Constants.restingShadowOpacity

    for (keyPath, from, to) in [
      ("shadowRadius", layer.presentation()?.shadowRadius ?? layer.shadowRadius, radius),
      ("shadowOpacity", CGFloat(layer.presentation()?.shadowOpacity ?? layer.shadowOpacity), CGFloat(opacity)),
    ] {
      let animation = CABasicAnimation(keyPath: keyPath)
      animation.fromValue = from
      animation.toValue = to
      animation.duration = 0.22
      animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
      layer.add(animation, forKey: keyPath)
    }

    layer.shadowRadius = radius
    layer.shadowOpacity = opacity
  }

  func setUpButtons() {
    buttons = actions.enumerated().map { index, action in
      let button = OverlayIconButton()
      if let customImage = action.customImage {
        button.image = customImage
      } else if let symbolName = action.currentSymbolName?() ?? action.symbolName {
        button.image = .with(
          symbolName: symbolName,
          pointSize: Constants.iconPointSize,
          weight: .medium,
          accessibilityLabel: action.accessibilityLabel
        )
      }
      if let isActive = action.isActive {
        button.contentTintColor = isActive() ? AppPreferences.Editor.accentColor.nsColor : nil
      }

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
    layerBackgroundColor = AppPreferences.Editor.accentColor.nsColor.withAlphaComponent(0.16)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    layerBackgroundColor = nil
  }
}
