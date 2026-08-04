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
  case ember
  case crimson
  case fern
  case teal
  case graphite

  var description: String {
    switch self {
    case .amber: return "Amber"
    case .ember: return "Ember"
    case .crimson: return "Crimson"
    case .fern: return "Fern"
    case .teal: return "Teal"
    case .graphite: return "Graphite"
    }
  }

  // Light values hold ≥4.5:1 contrast on white; dark values stay luminous on dark
  func hexCode(isDark: Bool) -> UInt32 {
    switch self {
    case .amber: return isDark ? 0xfbbf24 : 0xb45309
    case .ember: return isDark ? 0xfb923c : 0xc2410c
    case .crimson: return isDark ? 0xf87171 : 0xdc2626
    case .fern: return isDark ? 0x4ade80 : 0x15803d
    case .teal: return isDark ? 0x2dd4bf : 0x0f766e
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
