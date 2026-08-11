//
//  EditorSettingsView.swift
//  MarkEditMac
//
//  Created by cyan on 1/26/23.
//

import AppKit
import AppKitExtensions
import SwiftUI
import FontPicker
import SettingsUI
import SharedUI
import MarkEditCore
import MarkEditKit

@MainActor
struct EditorSettingsView: View {
  @Environment(\.colorScheme)
  private var colorScheme
  @State private var appearance = AppPreferences.General.appearance
  @State private var fontStyle = AppPreferences.Editor.fontStyle
  @State private var fontSize = AppPreferences.Editor.fontSize
  @State private var accentColor = AppPreferences.Editor.accentColor
  @State private var showLineNumbers = AppPreferences.Editor.showLineNumbers
  @State private var showActiveLineIndicator = AppPreferences.Editor.showActiveLineIndicator
  @State private var invisiblesBehavior = AppPreferences.Editor.invisiblesBehavior
  @State private var typewriterMode = AppPreferences.Editor.typewriterMode
  @State private var focusMode = AppPreferences.Editor.focusMode
  @State private var lineHeight = AppPreferences.Editor.lineHeight

  var body: some View {
    SettingsForm {
      Section {
        Picker(Localized.Settings.font, selection: $fontStyle) {
          ForEach(fontStyleOptions, id: \.self) {
            Text(fontStyleName($0)).tag($0)
          }
        }
        .onChange(of: fontStyle) {
          AppPreferences.Editor.fontStyle = fontStyle
        }
        .formMenuPicker()

        Stepper(value: $fontSize, in: FontPicker.minimumFontSize...FontPicker.maximumFontSize, step: 1) {
          Text(String(format: "%.1f", fontSize))
            .monospacedDigit()
        }
        .onChange(of: fontSize) {
          AppPreferences.Editor.fontSize = fontSize
        }
        .onReceive(NotificationCenter.default.publisher(for: .fontSizeChanged)) { _ in
          fontSize = AppPreferences.Editor.fontSize
        }
        .formLabel(Localized.Settings.fontSize)
      }

      Section {
        Picker(Localized.Settings.appearance, selection: $appearance) {
          Text(Localized.Settings.system).tag(Appearance.system)
          Divider()
          Text(Localized.Settings.light).tag(Appearance.light)
          Text(Localized.Settings.dark).tag(Appearance.dark)
        }
        .onChange(of: appearance) {
          NSApp.appearance = appearance.resolved()
          AppPreferences.General.appearance = appearance
        }
        .formMenuPicker()

        Picker(Localized.Settings.accentColor, selection: $accentColor) {
          ForEach(AppAccentColor.allCases, id: \.self) { color in
            Label {
              Text(color.description)
            } icon: {
              Image(nsImage: swatchImage(for: color))
            }
            .tag(color)
          }
        }
        .labelStyle(.titleAndIcon)
        .onChange(of: accentColor) {
          AppPreferences.Editor.accentColor = accentColor
        }
        .formMenuPicker()
        // Re-render the swatches when the app switches between light and dark
        .id(colorScheme)
      }

      Section {
        VStack(alignment: .leading) {
          Toggle(isOn: $showLineNumbers) {
            Text(Localized.Settings.lineNumbers)
          }
          .onChange(of: showLineNumbers) {
            AppPreferences.Editor.showLineNumbers = showLineNumbers
          }

          Toggle(isOn: $showActiveLineIndicator) {
            Text(Localized.Settings.activeLineIndicator)
          }
          .onChange(of: showActiveLineIndicator) {
            AppPreferences.Editor.showActiveLineIndicator = showActiveLineIndicator
          }
        }
        .formLabel(alignment: .top, Localized.Settings.displayOptions)

        Picker(Localized.Settings.renderInvisibles, selection: $invisiblesBehavior) {
          Text(Localized.Settings.never).tag(EditorInvisiblesBehavior.never)
          Text(Localized.Settings.selection).tag(EditorInvisiblesBehavior.selection)
          Text(Localized.Settings.trailing).tag(EditorInvisiblesBehavior.trailing)
          Text(Localized.Settings.always).tag(EditorInvisiblesBehavior.always)
        }
        .onChange(of: invisiblesBehavior) {
          AppPreferences.Editor.invisiblesBehavior = invisiblesBehavior
        }
        .formMenuPicker()
      }

      Section {
        VStack(alignment: .leading) {
          Toggle(isOn: $focusMode) {
            Text(Localized.Settings.focusModeTitle)
          }
          .onChange(of: focusMode) {
            AppPreferences.Editor.focusMode = focusMode
          }

          Toggle(isOn: $typewriterMode) {
            Text(Localized.Settings.typewriterModeTitle)
          }
          .onChange(of: typewriterMode) {
            AppPreferences.Editor.typewriterMode = typewriterMode
          }
        }
        .formLabel(alignment: .top, Localized.Settings.editBehavior)

        Picker(Localized.Settings.lineHeight, selection: $lineHeight) {
          Text(Localized.Settings.tightHeight).tag(LineHeight.tight)
          Text(Localized.Settings.normalHeight).tag(LineHeight.normal)
          Text(Localized.Settings.relaxedHeight).tag(LineHeight.relaxed)
        }
        .onChange(of: lineHeight) {
          AppPreferences.Editor.lineHeight = lineHeight
        }
        .formHorizontalRadio()
        .formBreathingInset()
      }
    }
  }
}

// MARK: - Private

private extension EditorSettingsView {
  func swatchImage(for color: AppAccentColor) -> NSImage {
    let hexCode = color.hexCode(isDark: colorScheme == .dark)
    return NSImage(size: CGSize(width: 12, height: 12), flipped: false) { rect in
      NSColor(hexCode: hexCode).setFill()
      NSBezierPath(ovalIn: rect).fill()
      return true
    }
  }

  var fontStyleOptions: [FontStyle] {
    var options: [FontStyle] = [.systemDefault, .systemSerif, .systemMono]

    // Keep a custom font selectable if one was configured (e.g. via settings.json)
    if case .customFont = fontStyle, !options.contains(fontStyle) {
      options.append(fontStyle)
    }

    return options
  }

  func fontStyleName(_ style: FontStyle) -> String {
    switch style {
    case .systemDefault:
      return Localized.Settings.systemDefault
    case .systemMono:
      return Localized.Settings.systemMono
    case .systemRounded:
      return Localized.Settings.systemRounded
    case .systemSerif:
      return Localized.Settings.systemSerif
    case .customFont(let name):
      return name
    }
  }
}
