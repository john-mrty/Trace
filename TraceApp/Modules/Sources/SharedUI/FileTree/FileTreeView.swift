//
//  FileTreeView.swift
//
//  Created by cyan on 8/9/26.
//

import AppKit
import AppKitExtensions

public enum FileTreeSortOrder: String, Codable, CaseIterable, Sendable {
  case alphabetical
  case created
  case modified
}

/**
 Obsidian-style folder tree: one root, lazy children, writing files only.

 Typography follows the chapter-indicator popover: small, grey, with the
 current document in full-strength semibold.
 */
public final class FileTreeView: NSView {
  public var onSelectFile: ((URL) -> Void)?

  public var rootURL: URL? {
    didSet {
      guard rootURL?.standardizedFileURL != oldValue?.standardizedFileURL else {
        return
      }

      reload()
    }
  }

  public var sortOrder: FileTreeSortOrder = .alphabetical {
    didSet {
      guard sortOrder != oldValue else {
        return
      }

      reload()
    }
  }

  private let fileExtensions: Set<String>
  private var rootNode: FileTreeNode?
  private var currentFileURL: URL?

  private let scrollView = NSScrollView()
  private let outlineView = FileTreeOutlineView()
  private let searchField = NSSearchField()

  private var searchQuery = ""
  private var searchMatches = [FileTreeNode]()
  private var preSearchExpandedPaths: Set<String>?

  private var isSearching: Bool {
    !searchQuery.isEmpty
  }

  public init(fileExtensions: Set<String>) {
    self.fileExtensions = fileExtensions
    super.init(frame: .zero)

    outlineView.headerView = nil
    outlineView.rowHeight = 22
    outlineView.indentationPerLevel = 12
    outlineView.autoresizesOutlineColumn = false
    outlineView.selectionHighlightStyle = .regular
    outlineView.backgroundColor = .clear
    outlineView.focusRingType = .none
    outlineView.rowSizeStyle = .custom
    outlineView.intercellSpacing = .zero

    let column = NSTableColumn(identifier: .init("name"))
    column.resizingMask = .autoresizingMask
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column

    outlineView.dataSource = self
    outlineView.delegate = self
    outlineView.target = self
    outlineView.action = #selector(handleClick(_:))
    outlineView.onActivateItem = { [weak self] in
      self?.activateSelectedRow()
    }
    outlineView.onNavigateLeft = { [weak self] in
      self?.navigateToParent() ?? false
    }
    outlineView.onNavigateRight = { [weak self] in
      self?.openSelectedFile() ?? false
    }

    scrollView.documentView = outlineView
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.scrollerStyle = .overlay
    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)
    addSubview(scrollView)

    searchField.controlSize = .small
    searchField.font = .systemFont(ofSize: 12)
    searchField.placeholderString = "Search"
    searchField.focusRingType = .none
    searchField.delegate = self
    addSubview(searchField)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override public func layout() {
    super.layout()

    // The scroll view stops below the search field, so rows clip there
    // instead of scrolling up behind the field and window controls
    let headerHeight = topInset + Constants.searchFieldHeight + Constants.searchFieldSpacing
    scrollView.frame = CGRect(
      x: 0,
      y: 0,
      width: bounds.width,
      height: max(0, bounds.height - headerHeight)
    )

    searchField.frame = CGRect(
      x: Constants.searchFieldPadding,
      y: bounds.height - topInset - Constants.searchFieldHeight,
      width: max(0, bounds.width - Constants.searchFieldPadding * 2),
      height: Constants.searchFieldHeight
    )
  }

  /// Top inset so the search field clears the titlebar area; set by the host.
  public var topInset: Double = 0 {
    didSet {
      needsLayout = true
    }
  }

  public func reload() {
    let expandedPaths = isSearching ? (preSearchExpandedPaths ?? []) : currentlyExpandedPaths()
    rootNode = rootURL.map {
      FileTreeNode(url: $0, isDirectory: true, fileExtensions: fileExtensions, sortOrder: sortOrder)
    }

    if isSearching {
      preSearchExpandedPaths = expandedPaths
      searchMatches = collectMatches(for: searchQuery)
      outlineView.reloadData()
      return
    }

    outlineView.reloadData()

    // Root's children show at level zero; re-expand what the user had open
    expandPaths(expandedPaths)
    selectCurrent(currentFileURL)
  }

  /// Expands ancestors and highlights the given file, if it lives under the root.
  public func reveal(_ url: URL?) {
    currentFileURL = url?.standardizedFileURL
    guard let url = currentFileURL, let rootNode else {
      return refreshVisibleRows()
    }

    let rootPath = rootNode.url.standardizedFileURL.path
    guard url.path.hasPrefix(rootPath + "/") else {
      return refreshVisibleRows()
    }

    // Expand each ancestor directory between the root and the file
    let relative = url.path.dropFirst(rootPath.count + 1).split(separator: "/").dropLast()
    var node = rootNode
    for component in relative {
      guard let child = (node.children.first { $0.url.lastPathComponent == component }) else {
        break
      }

      outlineView.expandItem(child)
      node = child
    }

    refreshVisibleRows()
    let row = outlineView.row(forItem: findNode(for: url))
    if row >= 0 {
      outlineView.selectRowIndexes([row], byExtendingSelection: false)
      outlineView.scrollRowToVisible(row)
    }
  }

  /// Updates the highlighted row without expanding anything.
  public func selectCurrent(_ url: URL?) {
    currentFileURL = url?.standardizedFileURL
    refreshVisibleRows()
  }

  /// Takes keyboard focus so arrow keys navigate the tree immediately.
  public func focus() {
    window?.makeFirstResponder(outlineView)
    if outlineView.selectedRow < 0, outlineView.numberOfRows > 0 {
      outlineView.selectRowIndexes([0], byExtendingSelection: false)
    }
  }
}

// MARK: - NSOutlineViewDataSource

extension FileTreeView: NSOutlineViewDataSource {
  public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if isSearching {
      return item == nil ? searchMatches.count : 0
    }

    return nodeOrRoot(item)?.children.count ?? 0
  }

  public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if isSearching {
      return searchMatches[index]
    }

    return nodeOrRoot(item)?.children[index] as Any
  }

  public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    if isSearching {
      return false
    }

    return (item as? FileTreeNode)?.isDirectory ?? false
  }
}

// MARK: - NSOutlineViewDelegate

extension FileTreeView: NSOutlineViewDelegate {
  public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? FileTreeNode else {
      return nil
    }

    let identifier = NSUserInterfaceItemIdentifier("FileTreeCell")
    let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? FileTreeCellView) ?? {
      let cell = FileTreeCellView()
      cell.identifier = identifier
      return cell
    }()

    let isCurrent = !node.isDirectory && node.url.standardizedFileURL == currentFileURL
    cell.configure(with: node, isCurrent: isCurrent)
    return cell
  }

  public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    let identifier = NSUserInterfaceItemIdentifier("FileTreeRow")
    if let row = outlineView.makeView(withIdentifier: identifier, owner: self) as? QuietRowView {
      return row
    }

    let row = QuietRowView()
    row.identifier = identifier
    return row
  }
}

// MARK: - NSSearchFieldDelegate

extension FileTreeView: NSSearchFieldDelegate {
  public func controlTextDidChange(_ obj: Notification) {
    updateSearchQuery(searchField.stringValue)
  }

  public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      if let first = searchMatches.first, isSearching {
        onSelectFile?(first.url)
      }
      return true
    case #selector(NSResponder.moveDown(_:)):
      focus()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      searchField.stringValue = ""
      updateSearchQuery("")
      focus()
      return true
    default:
      return false
    }
  }
}

// MARK: - Private

private extension FileTreeView {
  enum Constants {
    static let searchFieldHeight: Double = 26
    static let searchFieldSpacing: Double = 6
    static let searchFieldPadding: Double = 16
  }

  func updateSearchQuery(_ query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
      guard isSearching else {
        return
      }

      searchQuery = ""
      searchMatches = []
      outlineView.reloadData()

      // Put the tree back the way it was before the search started
      if let paths = preSearchExpandedPaths {
        expandPaths(paths)
      }

      preSearchExpandedPaths = nil
      selectCurrent(currentFileURL)
      return
    }

    if !isSearching {
      preSearchExpandedPaths = currentlyExpandedPaths()
    }

    searchQuery = trimmed
    searchMatches = collectMatches(for: trimmed)
    outlineView.reloadData()
  }

  /// Fuzzy filename match over the whole tree, best matches first.
  /// Walking `children` loads directories lazily from disk; the visit cap
  /// keeps a pathological folder from blocking the UI.
  func collectMatches(for query: String) -> [FileTreeNode] {
    guard let rootNode else {
      return []
    }

    var scored = [(node: FileTreeNode, score: Int)]()
    var stack = [rootNode]
    var visited = 0

    outer: while let node = stack.popLast() {
      for child in node.children {
        visited += 1
        if visited > 20_000 {
          break outer
        }

        if child.isDirectory {
          stack.append(child)
        } else if let score = FuzzyMatch.score(
          query: query,
          in: child.url.deletingPathExtension().lastPathComponent
        ) {
          scored.append((child, score))
        }
      }
    }

    return scored.sorted { $0.score > $1.score }.map(\.node)
  }

  func refreshVisibleRows() {
    outlineView.reloadData(
      forRowIndexes: IndexSet(integersIn: 0..<outlineView.numberOfRows),
      columnIndexes: [0]
    )
  }

  func nodeOrRoot(_ item: Any?) -> FileTreeNode? {
    (item as? FileTreeNode) ?? rootNode
  }

  func findNode(for url: URL) -> FileTreeNode? {
    for row in 0..<outlineView.numberOfRows {
      if let node = outlineView.item(atRow: row) as? FileTreeNode,
         node.url.standardizedFileURL == url {
        return node
      }
    }

    return nil
  }

  func currentlyExpandedPaths() -> Set<String> {
    var paths = Set<String>()
    for row in 0..<outlineView.numberOfRows {
      if let node = outlineView.item(atRow: row) as? FileTreeNode,
         outlineView.isItemExpanded(node) {
        paths.insert(node.url.standardizedFileURL.path)
      }
    }

    return paths
  }

  func expandPaths(_ paths: Set<String>) {
    guard !paths.isEmpty else {
      return
    }

    // Rows appear as parents expand; iterate until no new expansions happen
    var didExpand = true
    while didExpand {
      didExpand = false
      for row in 0..<outlineView.numberOfRows {
        if let node = outlineView.item(atRow: row) as? FileTreeNode,
           paths.contains(node.url.standardizedFileURL.path),
           !outlineView.isItemExpanded(node) {
          outlineView.expandItem(node)
          didExpand = true
        }
      }
    }
  }

  func activate(_ node: FileTreeNode) {
    if node.isDirectory {
      if outlineView.isItemExpanded(node) {
        outlineView.animator().collapseItem(node)
      } else {
        outlineView.animator().expandItem(node)
      }
    } else {
      onSelectFile?(node.url)
    }
  }

  func activateSelectedRow() {
    guard let node = outlineView.item(atRow: outlineView.selectedRow) as? FileTreeNode else {
      return
    }

    activate(node)
  }

  @objc func handleClick(_ sender: Any?) {
    // Take keyboard focus so arrow-key navigation works right away
    window?.makeFirstResponder(outlineView)

    guard let node = outlineView.item(atRow: outlineView.clickedRow) as? FileTreeNode else {
      return
    }

    activate(node)
  }

  /// Right arrow on a file opens it; folders fall through to the native expand.
  func openSelectedFile() -> Bool {
    guard let node = outlineView.item(atRow: outlineView.selectedRow) as? FileTreeNode, !node.isDirectory else {
      return false
    }

    onSelectFile?(node.url)
    return true
  }

  /// Obsidian-style Left arrow: on a file (or collapsed folder), jump to the parent folder.
  func navigateToParent() -> Bool {
    guard let node = outlineView.item(atRow: outlineView.selectedRow) as? FileTreeNode else {
      return false
    }

    if node.isDirectory && outlineView.isItemExpanded(node) {
      return false // Let the outline view collapse it natively
    }

    guard let parent = outlineView.parent(forItem: node) else {
      return false
    }

    let row = outlineView.row(forItem: parent)
    guard row >= 0 else {
      return false
    }

    outlineView.selectRowIndexes([row], byExtendingSelection: false)
    outlineView.scrollRowToVisible(row)
    return true
  }
}

// MARK: - FileTreeNode

private final class FileTreeNode {
  let url: URL
  let isDirectory: Bool

  private let fileExtensions: Set<String>
  private let sortOrder: FileTreeSortOrder
  private var cachedChildren: [FileTreeNode]?
  private var creationDate: Date = .distantPast
  private var modificationDate: Date = .distantPast

  init(url: URL, isDirectory: Bool, fileExtensions: Set<String>, sortOrder: FileTreeSortOrder) {
    self.url = url
    self.isDirectory = isDirectory
    self.fileExtensions = fileExtensions
    self.sortOrder = sortOrder
  }

  var children: [FileTreeNode] {
    if let cachedChildren {
      return cachedChildren
    }

    let keys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: Array(keys),
      options: .skipsHiddenFiles
    )) ?? []

    let nodes: [FileTreeNode] = contents.compactMap { child in
      let values = try? child.resourceValues(forKeys: keys)
      let isDirectory = values?.isDirectory ?? false
      if isDirectory {
        guard child.lastPathComponent != "node_modules", Self.containsWritingFile(child, fileExtensions: fileExtensions) else {
          return nil
        }
      } else {
        guard fileExtensions.contains(child.pathExtension.lowercased()) else {
          return nil
        }
      }

      let node = FileTreeNode(url: child, isDirectory: isDirectory, fileExtensions: fileExtensions, sortOrder: sortOrder)
      node.creationDate = values?.creationDate ?? .distantPast
      node.modificationDate = values?.contentModificationDate ?? .distantPast
      return node
    }

    let sorted = nodes.sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory {
        return lhs.isDirectory
      }

      switch sortOrder {
      case .alphabetical:
        return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
      case .created:
        return lhs.creationDate > rhs.creationDate
      case .modified:
        return lhs.modificationDate > rhs.modificationDate
      }
    }

    cachedChildren = sorted
    return sorted
  }

  /// Early-exit scan: true once any writing file is found. Fails open past the
  /// visit cap so a pathological subtree can't hide itself or block the UI.
  private static func containsWritingFile(_ folder: URL, fileExtensions: Set<String>) -> Bool {
    guard let enumerator = FileManager.default.enumerator(
      at: folder,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return false
    }

    var visited = 0
    for case let url as URL in enumerator {
      if url.lastPathComponent == "node_modules" {
        enumerator.skipDescendants()
        continue
      }

      if fileExtensions.contains(url.pathExtension.lowercased()) {
        return true
      }

      visited += 1
      if visited > 2000 {
        return true
      }
    }

    return false
  }
}

// MARK: - Views

private final class FileTreeOutlineView: NSOutlineView {
  var onActivateItem: (() -> Void)?
  var onNavigateLeft: (() -> Bool)?
  var onNavigateRight: (() -> Bool)?

  override func frameOfOutlineCell(atRow row: Int) -> CGRect {
    // Default chevron sits too far left with tight indentation; nudge it in
    var frame = super.frameOfOutlineCell(atRow: row)
    frame.origin.x += 4
    return frame
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == .kVK_Return, selectedRow >= 0 {
      onActivateItem?()
      return
    }

    if event.keyCode == .kVK_LeftArrow, onNavigateLeft?() == true {
      return
    }

    if event.keyCode == .kVK_RightArrow, onNavigateRight?() == true {
      return
    }

    super.keyDown(with: event)
  }
}

private final class QuietRowView: NSTableRowView {
  // Emphasized (first-responder) selection flips labels to white; our pill
  // is quaternary grey, so keep the normal text colors
  override var isEmphasized: Bool {
    get { false }
    set {}
  }

  override func drawSelection(in dirtyRect: CGRect) {
    guard selectionHighlightStyle != .none else {
      return
    }

    NSColor.labelColor.withAlphaComponent(0.06).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 12, dy: 1.5), xRadius: 5, yRadius: 5).fill()
  }
}

private final class FileTreeCellView: NSView {
  private let iconView = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private var isFolder = false

  override init(frame: CGRect) {
    super.init(frame: frame)

    iconView.contentTintColor = .tertiaryLabelColor
    addSubview(iconView)

    label.lineBreakMode = .byTruncatingMiddle
    label.cell?.truncatesLastVisibleLine = true
    addSubview(label)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(with node: FileTreeNode, isCurrent: Bool) {
    isFolder = node.isDirectory
    label.stringValue = node.isDirectory ? node.url.lastPathComponent : node.url.deletingPathExtension().lastPathComponent

    // Chapter-indicator styling: grey rows, current one in full-strength semibold
    label.font = .systemFont(ofSize: 12, weight: isCurrent ? .semibold : .regular)
    label.textColor = isCurrent ? .labelColor : .secondaryLabelColor

    if node.isDirectory {
      iconView.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
    } else {
      iconView.image = nil
    }

    needsLayout = true
  }

  override func layout() {
    super.layout()

    let iconWidth: Double = isFolder ? 17 : 0
    iconView.frame = CGRect(x: 6, y: (bounds.height - 13) * 0.5, width: 13, height: 13)
    label.sizeToFit()
    label.frame = CGRect(
      x: 6 + iconWidth,
      y: (bounds.height - label.frame.height) * 0.5,
      width: max(0, bounds.width - iconWidth - 14),
      height: label.frame.height
    )
  }
}
