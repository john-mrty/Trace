//
//  CommandPaletteWindow.swift
//
//  Created by cyan on 8/6/26.
//

import AppKit
import AppKitExtensions

public struct CommandPaletteItem {
  public let title: String
  public let subtitle: String
  public let shortcut: String
  public let isOn: Bool
  public let action: () -> Void

  public init(title: String, subtitle: String = "", shortcut: String = "", isOn: Bool = false, action: @escaping () -> Void) {
    self.title = title
    self.subtitle = subtitle
    self.shortcut = shortcut
    self.isOn = isOn
    self.action = action
  }
}

public final class CommandPaletteWindow: NSWindow {
  private enum Constants {
    static let width: Double = 560
    // Transparent inset around the palette so the custom soft shadow has room to render
    static let shadowMargin: Double = 48
  }

  public init(
    effectViewType: NSView.Type,
    relativeTo parentRect: CGRect,
    placeholder: String,
    font: NSFont,
    caretColor: NSColor? = nil,
    items: [CommandPaletteItem]
  ) {
    self.caretColor = caretColor
    // Vertically centered at full height; the top edge stays put as the list filters down
    let initialHeight = CommandPaletteView.contentHeight(forItemCount: items.count)
    let margin = Constants.shadowMargin
    let rect = CGRect(
      x: parentRect.minX + (parentRect.width - Constants.width) * 0.5 - margin,
      y: parentRect.midY - initialHeight * 0.5 - margin,
      width: Constants.width + margin * 2,
      height: initialHeight + margin * 2
    )

    super.init(
      contentRect: rect,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )

    let paletteView = CommandPaletteView(
      effectViewType: effectViewType,
      frame: CGRect(x: margin, y: margin, width: Constants.width, height: initialHeight),
      placeholder: placeholder,
      font: font,
      items: items
    )

    // Fixed margins on all sides as the window resizes
    paletteView.autoresizingMask = [.width, .height]

    let containerView = NSView(frame: CGRect(origin: .zero, size: rect.size))
    containerView.addSubview(paletteView)

    self.contentView = containerView
    self.isMovableByWindowBackground = true
    self.isOpaque = false
    self.hasShadow = false
    self.backgroundColor = .clear

    paletteView.updateWindowHeight = { [weak self] height in
      guard let self else {
        return
      }

      let frame = self.frame
      let windowHeight = height + margin * 2
      self.setFrame(
        CGRect(x: frame.minX, y: frame.maxY - windowHeight, width: frame.width, height: windowHeight),
        display: true
      )
    }

    paletteView.applyContentHeight()
    self.paletteView = paletteView
  }

  private let caretColor: NSColor?
  private weak var paletteView: CommandPaletteView?

  override public func makeKeyAndOrderFront(_ sender: Any?) {
    super.makeKeyAndOrderFront(sender)
    paletteView?.beginEditing(caretColor: caretColor)
  }

  override public var canBecomeKey: Bool {
    true
  }

  override public func resignKey() {
    orderOut(self)
  }

  override public func cancelOperation(_ sender: Any?) {
    orderOut(self)
  }
}

// MARK: - Palette View

private final class CommandPaletteView: NSView {
  private enum Constants {
    static let cornerRadius: Double = 12
    static let padding: Double = 8
    static let fieldHeight: Double = 48
    static let rowHeight: Double = 36
    static let maxVisibleRows = 8
  }

  static func contentHeight(forItemCount count: Int) -> Double {
    let rowCount = min(count, Constants.maxVisibleRows)
    let listHeight = count == 0 ? 0 : Double(rowCount) * Constants.rowHeight + Constants.padding
    return Constants.fieldHeight + listHeight
  }

  var updateWindowHeight: ((Double) -> Void)?

  private let effectViewType: NSView.Type
  private let baseFont: NSFont
  private let allItems: [CommandPaletteItem]
  private var filteredItems: [CommandPaletteItem]

  private lazy var effectView: NSView = {
    let effectView = effectViewType.init()
    (effectView as? NSVisualEffectView)?.material = .popover

    // Rounding lives here so the container layer can carry an unclipped shadow
    effectView.wantsLayer = true
    effectView.layer?.cornerCurve = .continuous
    effectView.layer?.cornerRadius = Constants.cornerRadius
    effectView.layer?.masksToBounds = true

    return effectView
  }()

  private let textField: NSTextField = {
    let textField = NSTextField()
    textField.focusRingType = .none
    textField.drawsBackground = false
    textField.isBezeled = false

    return textField
  }()

  private let tableView: NSTableView = {
    let tableView = NSTableView()
    tableView.headerView = nil
    tableView.backgroundColor = .clear
    tableView.rowHeight = Constants.rowHeight
    tableView.style = .inset
    tableView.intercellSpacing = .zero
    tableView.allowsEmptySelection = false

    let column = NSTableColumn(identifier: .init("command"))
    tableView.addTableColumn(column)

    return tableView
  }()

  private let scrollView: NSScrollView = {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true

    return scrollView
  }()

  init(
    effectViewType: NSView.Type,
    frame: CGRect,
    placeholder: String,
    font: NSFont,
    items: [CommandPaletteItem]
  ) {
    self.effectViewType = effectViewType
    self.baseFont = font
    self.allItems = items
    self.filteredItems = items
    super.init(frame: frame)

    textField.font = baseFont

    wantsLayer = true
    layer?.cornerCurve = .continuous
    layer?.cornerRadius = Constants.cornerRadius

    // NSShadow survives AppKit's layer management; raw layer?.shadow* gets clobbered
    let dropShadow = NSShadow()
    dropShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    dropShadow.shadowBlurRadius = 24
    dropShadow.shadowOffset = CGSize(width: 0, height: -10)
    shadow = dropShadow

    effectView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(effectView)

    // Wash over the blur so the palette reads close to the canvas background
    let tintView = CanvasTintView()
    tintView.translatesAutoresizingMaskIntoConstraints = false
    effectView.addSubview(tintView)

    textField.placeholderString = placeholder
    textField.delegate = self
    textField.translatesAutoresizingMaskIntoConstraints = false
    addSubview(textField)

    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.action = #selector(didClickRow(_:))

    scrollView.documentView = tableView
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scrollView)

    // Rows compute hover from the live cursor position; repaint them on
    // scroll so the state stays in sync as rows move under the cursor
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(scrollViewDidScroll(_:)),
      name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView
    )

    NSLayoutConstraint.activate([
      effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      effectView.topAnchor.constraint(equalTo: topAnchor),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

      tintView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
      tintView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
      tintView.topAnchor.constraint(equalTo: effectView.topAnchor),
      tintView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),

      textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.padding * 2),
      textField.centerYAnchor.constraint(equalTo: topAnchor, constant: Constants.fieldHeight * 0.5),
      textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.padding),

      scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.fieldHeight),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      // Flush to the bottom: the viewport keeps padding-worth of slack below the
      // last row, so its rounded highlight never clips against the corner mask
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    tableView.reloadData()
    selectRow(0)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func applyContentHeight() {
    updateWindowHeight?(Self.contentHeight(forItemCount: filteredItems.count))
  }

  func beginEditing(caretColor: NSColor?) {
    window?.makeFirstResponder(textField)

    if let caretColor, let editor = textField.currentEditor() as? NSTextView {
      editor.insertionPointColor = caretColor
    }
  }
}

// MARK: - NSTextFieldDelegate

extension CommandPaletteView: NSTextFieldDelegate {
  func controlTextDidChange(_ notification: Notification) {
    filteredItems = Self.filter(items: allItems, query: textField.stringValue)
    tableView.reloadData()
    selectRow(0)
    applyContentHeight()
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(insertNewline(_:)):
      performSelectedItem()
      return true
    case #selector(moveUp(_:)):
      selectRow(tableView.selectedRow - 1)
      return true
    case #selector(moveDown(_:)):
      selectRow(tableView.selectedRow + 1)
      return true
    case #selector(cancelOperation(_:)):
      window?.orderOut(self)
      return true
    default:
      return false
    }
  }
}

// MARK: - NSTableViewDataSource, NSTableViewDelegate

extension CommandPaletteView: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    filteredItems.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let item = filteredItems[row]
    let cellView = NSView()

    let titleLabel = LabelView(frame: .zero)
    titleLabel.stringValue = item.isOn ? "✓ \(item.title)" : item.title
    titleLabel.font = scaledFont(delta: -1)
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    cellView.addSubview(titleLabel)

    let detailLabel = LabelView(frame: .zero)
    detailLabel.stringValue = item.subtitle
    detailLabel.font = scaledFont(delta: -3)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byTruncatingMiddle
    detailLabel.translatesAutoresizingMaskIntoConstraints = false
    cellView.addSubview(detailLabel)

    let shortcutLabel = LabelView(frame: .zero)
    shortcutLabel.stringValue = item.shortcut
    shortcutLabel.font = scaledFont(delta: -2)
    shortcutLabel.textColor = .tertiaryLabelColor
    shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
    cellView.addSubview(shortcutLabel)

    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    detailLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: Constants.padding),
      titleLabel.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),

      detailLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: Constants.padding),
      detailLabel.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -Constants.padding),

      shortcutLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -Constants.padding),
      shortcutLabel.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
    ])

    return cellView
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    RoundedRowView()
  }
}

// MARK: - Private

private extension CommandPaletteView {
  func scaledFont(delta: Double) -> NSFont {
    NSFont(descriptor: baseFont.fontDescriptor, size: baseFont.pointSize + delta) ?? baseFont
  }

  @objc func didClickRow(_ sender: NSTableView) {
    performSelectedItem()
  }

  @objc func scrollViewDidScroll(_ notification: Notification) {
    tableView.enumerateAvailableRowViews { rowView, _ in
      rowView.needsDisplay = true
    }
  }

  func selectRow(_ row: Int) {
    guard !filteredItems.isEmpty else {
      return
    }

    let clamped = max(0, min(row, filteredItems.count - 1))
    tableView.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
    tableView.scrollRowToVisible(clamped)
  }

  func performSelectedItem() {
    let row = tableView.selectedRow
    guard row >= 0 && row < filteredItems.count else {
      NSSound.beep()
      return
    }

    let item = filteredItems[row]
    window?.orderOut(self)

    // Run after key status returns to the editor window,
    // menu actions resolve against the first responder
    DispatchQueue.main.async {
      item.action()
    }
  }

  static func filter(items: [CommandPaletteItem], query: String) -> [CommandPaletteItem] {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else {
      return items
    }

    return items
      .compactMap { item -> (item: CommandPaletteItem, score: Int)? in
        let titleScore = FuzzyMatch.score(query: query, in: item.title).map { $0 + 100 }
        let subtitleScore = FuzzyMatch.score(query: query, in: item.subtitle)
        guard let score = [titleScore, subtitleScore].compactMap({ $0 }).max() else {
          return nil
        }

        return (item, score)
      }
      .sorted { $0.score > $1.score }
      .map { $0.item }
  }
}

// Resolved in updateLayer so the color follows the effective appearance,
// a cgColor snapshot at init bakes in whichever appearance was current then
private final class CanvasTintView: NSView {
  override var wantsUpdateLayer: Bool {
    true
  }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.65).cgColor
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

private final class RoundedRowView: NSTableRowView {
  // Hover is computed from the live cursor position at draw time instead of
  // being latched by enter/exit events: rows are reused, and scrolling moves
  // rows under a stationary cursor without firing mouseExited — both leave
  // stale "hovered" rows behind
  private var isMouseInside: Bool {
    guard let window else {
      return false
    }

    let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
    return visibleRect.contains(point)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)

    addTrackingArea(NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    ))
  }

  override func mouseEntered(with event: NSEvent) {
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    needsDisplay = true
  }

  override func drawBackground(in dirtyRect: NSRect) {
    super.drawBackground(in: dirtyRect)

    if isMouseInside && !isSelected {
      fillRoundedRow(color: NSColor.labelColor.withAlphaComponent(0.045))
    }
  }

  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else {
      return
    }

    fillRoundedRow(color: NSColor.labelColor.withAlphaComponent(0.08))
  }

  private func fillRoundedRow(color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
  }
}
