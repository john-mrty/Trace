//
//  EditorSettingsView.swift
//  MarkEditMac
//
//  Created by cyan on 1/26/23.
//

import AppKit
import SwiftUI
import FontPicker
import SettingsUI
import SharedUI
import MarkEditCore
import MarkEditKit

@MainActor
struct EditorSettingsView: View {
  @State private var accentColor = AppPreferences.Editor.accentColor
  @State private var showActiveLineIndicator = AppPreferences.Editor.showActiveLineIndicator
  @State private var invisiblesBehavior = AppPreferences.Editor.invisiblesBehavior
  @State private var typewriterMode = AppPreferences.Editor.typewriterMode
  @State private var focusMode = AppPreferences.Editor.focusMode
  @State private var lineWrapping = AppPreferences.Editor.lineWrapping
  @State private var lineHeight = AppPreferences.Editor.lineHeight
  @State private var tabKeyBehavior = AppPreferences.Editor.tabKeyBehavior
  @State private var indentUnit = AppPreferences.Editor.indentUnit

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(Localized.Settings.font)
        FontPicker(configuration: fontPickerConfiguration, handlers: fontPickerHandlers)
      }

      Divider()

      SettingsForm {
        Section {
          Picker(Localized.Settings.accentColor, selection: $accentColor) {
            ForEach(AppAccentColor.allCases, id: \.self) {
              Text($0.description).tag($0)
            }
          }
          .onChange(of: accentColor) {
            AppPreferences.Editor.accentColor = accentColor
          }
          .formMenuPicker()
        }

        Section {
          VStack(alignment: .leading) {
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
            Toggle(isOn: $typewriterMode) {
              Text(Localized.Settings.typewriterModeTitle)
            }
            .onChange(of: typewriterMode) {
              AppPreferences.Editor.typewriterMode = typewriterMode
            }

            Toggle(isOn: $focusMode) {
              Text(Localized.Settings.focusModeTitle)
            }
            .onChange(of: focusMode) {
              AppPreferences.Editor.focusMode = focusMode
            }
          }
          .formLabel(alignment: .top, Localized.Settings.editBehavior)

          Toggle(isOn: $lineWrapping) {
            Text(Localized.Settings.lineWrappingDescription)
          }
          .onChange(of: lineWrapping) {
            AppPreferences.Editor.lineWrapping = lineWrapping
          }
          .formLabel(Localized.Settings.lineWrappingLabel)
          .formBreathingInset()

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

        Section {
          Picker(Localized.Settings.tabKeyBehavior, selection: $tabKeyBehavior) {
            Text(Localized.Settings.insertsTab).tag(TabKeyBehavior.insertTab)
            Text(Localized.Settings.insertsTwoSpaces).tag(TabKeyBehavior.insertTwoSpaces)
            Text(Localized.Settings.insertsFourSpaces).tag(TabKeyBehavior.insertFourSpaces)
            Text(Localized.Settings.indentsMore).tag(TabKeyBehavior.indentMore)
          }
          .onChange(of: tabKeyBehavior) {
            AppPreferences.Editor.tabKeyBehavior = tabKeyBehavior
          }
          .formMenuPicker()

          Picker(Localized.Settings.indentUnit, selection: $indentUnit) {
            Text(Localized.Settings.twoSpaces).tag(IndentUnit.twoSpaces)
            Text(Localized.Settings.fourSpaces).tag(IndentUnit.fourSpaces)
            Text(Localized.Settings.oneTab).tag(IndentUnit.oneTab)
            Text(Localized.Settings.twoTabs).tag(IndentUnit.twoTabs)
          }
          .onChange(of: indentUnit) {
            AppPreferences.Editor.indentUnit = indentUnit
          }
          .formMenuPicker()
        }
      }
    }
  }
}

// MARK: - Private

private extension EditorSettingsView {
  var fontPickerConfiguration: FontPickerConfiguration {
    FontPickerConfiguration(
      modernStyle: AppDesign.modernStyle,
      selectedFontStyle: AppPreferences.Editor.fontStyle,
      selectedFontSize: AppPreferences.Editor.fontSize,
      selectButtonTitle: Localized.Settings.selectFont,
      recentlyUsedItemTitle: Localized.Settings.recentlyUsed,
      moreFontsItemTitle: Localized.Settings.moreFonts,
      openPanelItemTitle: Localized.Settings.openFontPanel,
      defaultFontName: Localized.Settings.systemDefault,
      monoFontName: Localized.Settings.systemMono,
      roundedFontName: Localized.Settings.systemRounded,
      serifFontName: Localized.Settings.systemSerif
    )
  }

  var fontPickerHandlers: FontPickerHandlers {
    FontPickerHandlers(
      fontStyleDidChange: { fontStyle in
        AppPreferences.Editor.fontStyle = fontStyle
      },
      fontSizeDidChange: { fontSize in
        AppPreferences.Editor.fontSize = fontSize
      }
    )
  }
}
