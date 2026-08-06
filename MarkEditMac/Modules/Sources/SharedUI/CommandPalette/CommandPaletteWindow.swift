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
  public let action: () -> Void

  public init(title: String, subtitle: String = "", shortcut: String = "", action: @escaping () -> Void) {
    self.title = title
    self.subtitle = subtitle
    self.shortcut = shortcut
    self.action = action
  }
}

public final class CommandPaletteWindow: NSWindow {
  private enum Constants {
    static let width: Double = 560
  }

  public init(
    effectViewType: NSView.Type,
    relativeTo parentRect: CGRect,
    placeholder: String,
    font: NSFont,
    items: [CommandPaletteItem]
  ) {
    // Vertically centered at full height; the top edge stays put as the list filters down
    let initialHeight = CommandPaletteView.contentHeight(forItemCount: items.count)
    let rect = CGRect(
      x: parentRect.minX + (parentRect.width - Constants.width) * 0.5,
      y: parentRect.midY - initialHeight * 0.5,
      width: Constants.width,
      height: initialHeight
    )

    super.init(
      contentRect: rect,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )

    let paletteView = CommandPaletteView(
      effectViewType: effectViewType,
      frame: CGRect(origin: .zero, size: rect.size),
      placeholder: placeholder,
      font: font,
      items: items
    )

    self.contentView = paletteView
    self.isMovableByWindowBackground = true
    self.isOpaque = false
    self.hasShadow = true
    self.backgroundColor = .clear

    paletteView.updateWindowHeight = { [weak self] height in
      guard let self else {
        return
      }

      let frame = self.frame
      self.setFrame(
        CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height),
        display: true
      )
    }

    paletteView.applyContentHeight()
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

    textField.font = scaledFont(delta: 6)

    wantsLayer = true
    layer?.cornerCurve = .continuous
    layer?.cornerRadius = Constants.cornerRadius

    effectView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(effectView)

    let iconView = NSImageView(image: .with(symbolName: "command", pointSize: 20, weight: .light))
    iconView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconView)

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

    NSLayoutConstraint.activate([
      effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      effectView.topAnchor.constraint(equalTo: topAnchor),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

      iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.padding * 2),
      iconView.topAnchor.constraint(equalTo: topAnchor, constant: (Constants.fieldHeight - 24) * 0.5),
      iconView.heightAnchor.constraint(equalToConstant: iconView.frame.height),
      iconView.widthAnchor.constraint(equalToConstant: iconView.frame.width),

      textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Constants.padding),
      textField.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
      textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.padding),

      scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.fieldHeight),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.padding),
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
    titleLabel.stringValue = item.title
    titleLabel.font = baseFont
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    cellView.addSubview(titleLabel)

    let detailLabel = LabelView(frame: .zero)
    detailLabel.stringValue = item.subtitle
    detailLabel.font = scaledFont(delta: -2)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.lineBreakMode = .byTruncatingMiddle
    detailLabel.translatesAutoresizingMaskIntoConstraints = false
    cellView.addSubview(detailLabel)

    let shortcutLabel = LabelView(frame: .zero)
    shortcutLabel.stringValue = item.shortcut
    shortcutLabel.font = scaledFont(delta: -1)
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
        let titleScore = fuzzyScore(query: query, in: item.title).map { $0 + 100 }
        let subtitleScore = fuzzyScore(query: query, in: item.subtitle)
        guard let score = [titleScore, subtitleScore].compactMap({ $0 }).max() else {
          return nil
        }

        return (item, score)
      }
      .sorted { $0.score > $1.score }
      .map { $0.item }
  }

  /// Case-insensitive subsequence match, higher is better, nil means no match.
  /// Contiguous matches beat scattered ones ("h2" hits both "Header 2" and "H2").
  static func fuzzyScore(query: String, in text: String) -> Int? {
    let query = Array(query.lowercased())
    let text = Array(text.lowercased())

    if let range = text.firstRange(of: query) {
      return 1000 - range.lowerBound
    }

    var score = 500
    var textIndex = 0

    for char in query {
      var found = false
      while textIndex < text.count {
        if text[textIndex] == char {
          found = true
          textIndex += 1
          break
        }

        score -= 1
        textIndex += 1
      }

      if !found {
        return nil
      }
    }

    return score
  }
}

private final class RoundedRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    guard selectionHighlightStyle != .none else {
      return
    }

    NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
  }
}
