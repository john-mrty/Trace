//
//  AppTheme.swift
//  MarkEditMac
//
//  Created by cyan on 12/17/22.
//

import AppKit

struct AppTheme {
  let isDark: Bool
  let editorTheme: String
  // Pre-defined colors to style the window for initial launch
  let windowBackground: NSColor
  // If true, the toolbar has more tinted effect based on windowBackground,
  // usually it's for dark themes, some light themes also need this, such as solarized.
  let prefersTintedToolbar: Bool

  @MainActor static var current: Self {
    NSApplication.shared.isDarkMode ? darkTheme : lightTheme
  }

  static func withName(_ name: String) -> Self {
    allCases.first { $0.editorTheme == name } ?? GitHubLight
  }

  /// Get a "resolved" appearance name based on the current effective appearance.
  @MainActor var resolvedAppearance: NSAppearance? {
    NSAppearance(named: NSApp.effectiveAppearance.resolvedName(isDarkMode: isDark))
  }

  /// Trigger theme update for all editors.
  @MainActor
  func updateAppearance(animateChanges: Bool = false) {
    EditorPreloader.shared.viewControllers().forEach {
      $0.setTheme(self, animated: animateChanges)
    }
  }
}

// MARK: - Themes

extension AppTheme: CaseIterable, Hashable, CustomStringConvertible {
  static var allCases: [AppTheme] {
    [
      GitHubLight, GitHubDark,
      MinimalLight, MinimalDark,
    ]
  }

  static var GitHubLight: Self {
    Self(
      isDark: false,
      editorTheme: "github-light",
      windowBackground: NSColor(hexCode: 0xffffff),
      prefersTintedToolbar: false
    )
  }

  static var GitHubDark: Self {
    Self(
      isDark: true,
      editorTheme: "github-dark",
      windowBackground: NSColor(hexCode: 0x0d1116),
      prefersTintedToolbar: true
    )
  }

  static var MinimalLight: Self {
    Self(
      isDark: false,
      editorTheme: "minimal-light",
      windowBackground: NSColor(hexCode: 0xffffff),
      prefersTintedToolbar: false
    )
  }

  static var MinimalDark: Self {
    Self(
      isDark: true,
      editorTheme: "minimal-dark",
      windowBackground: NSColor(hexCode: 0x1e1e1e),
      prefersTintedToolbar: true
    )
  }

  var description: String {
    switch self {
    case Self.GitHubLight:
      return "GitHub (Light)"
    case Self.GitHubDark:
      return "GitHub (Dark)"
    case Self.MinimalLight:
      return "Minimal (Light)"
    case Self.MinimalDark:
      return "Minimal (Dark)"
    default:
      fatalError("Invalid theme was found")
    }
  }
}

/// User-selectable accent, applied to the editor caret/selection and FAB states.
enum AppAccentColor: String, Codable, CaseIterable, CustomStringConvertible {
  case amber
  case terracotta
  case clay
  case moss
  case teal
  case graphite

  var description: String {
    switch self {
    case .amber: return "Amber"
    case .terracotta: return "Terracotta"
    case .clay: return "Clay"
    case .moss: return "Moss"
    case .teal: return "Teal"
    case .graphite: return "Graphite"
    }
  }

  func hexCode(isDark: Bool) -> UInt32 {
    switch self {
    case .amber: return isDark ? 0xe0a458 : 0x9a6b1f
    case .terracotta: return isDark ? 0xe8926d : 0xa84a2a
    case .clay: return isDark ? 0xe57e70 : 0x9e3a30
    case .moss: return isDark ? 0xa8b665 : 0x5a6b34
    case .teal: return isDark ? 0x6fb5b0 : 0x26666a
    case .graphite: return isDark ? 0xd0d0d0 : 0x3d3d3d
    }
  }

  var nsColor: NSColor {
    NSColor(name: nil) { appearance in
      NSColor(hexCode: self.hexCode(isDark: appearance.isDarkMode))
    }
  }

  func cssCaretColor(isDark: Bool) -> String {
    String(format: "#%06x", hexCode(isDark: isDark))
  }

  func cssSelectionColor(isDark: Bool) -> String {
    // ~30% wash so text stays readable through the selection
    String(format: "#%06x4d", hexCode(isDark: isDark))
  }
}

@MainActor
extension AppTheme {
  // Stored names can reference removed themes or a mismatched appearance
  // (e.g. a light theme saved as the dark choice); resolve to a sane default.
  static var lightTheme: Self {
    let theme = withName(AppPreferences.Editor.lightTheme)
    return theme.isDark ? GitHubLight : theme
  }

  static var darkTheme: Self {
    let theme = withName(AppPreferences.Editor.darkTheme)
    return theme.isDark ? theme : GitHubDark
  }
}
