//
//  GeneralSettingsView.swift
//  MarkEditMac
//
//  Created by cyan on 1/26/23.
//

import SwiftUI
import SettingsUI
import MarkEditKit

@MainActor
struct GeneralSettingsView: View {
  @State private var newWindowBehavior = AppPreferences.General.newWindowBehavior
  @State private var quitAlwaysKeepsWindows = AppPreferences.General.quitAlwaysKeepsWindows
  @State private var newFilenameExtension = AppPreferences.General.newFilenameExtension
  @State private var defaultTextEncoding = AppPreferences.General.defaultTextEncoding
  @State private var defaultLineEndings = AppPreferences.General.defaultLineEndings
  @State private var tabbingMode = AppPreferences.Window.tabbingMode
  @State private var reduceTransparency = AppPreferences.Window.reduceTransparency
  @State private var sidebarRootPath = Self.resolvedSidebarRootPath()

  var body: some View {
    SettingsForm {
      Section {
        Picker(Localized.Settings.newWindowBehavior, selection: $newWindowBehavior) {
          Text(Localized.Document.openDocument).tag(NewWindowBehavior.openDocument)
          Text(Localized.Document.newDocument).tag(NewWindowBehavior.newDocument)
        }
        .onChange(of: newWindowBehavior) {
          AppPreferences.General.newWindowBehavior = newWindowBehavior
        }
        .formMenuPicker()

        Toggle(Localized.Settings.quitAlwaysKeepsWindows, isOn: $quitAlwaysKeepsWindows)
          .onChange(of: quitAlwaysKeepsWindows) {
            AppPreferences.General.quitAlwaysKeepsWindows = quitAlwaysKeepsWindows
          }
          .formLabel(Localized.Settings.windowRestoration)
          .formBreathingInset()
      }

      Section {
        Picker(Localized.Settings.newFilenameExtension, selection: $newFilenameExtension) {
          ForEach(NewFilenameExtension.allCases, id: \.self) {
            Text($0.rawValue).tag($0)
          }
        }
        .onChange(of: newFilenameExtension) {
          AppPreferences.General.newFilenameExtension = newFilenameExtension
        }
        .formMenuPicker()

        Picker(Localized.Settings.defaultTextEncoding, selection: $defaultTextEncoding) {
          ForEach(EditorTextEncoding.allCases, id: \.self) {
            Text($0.description)

            if EditorTextEncoding.groupingCases.contains($0) {
              Divider()
            }
          }
        }
        .onChange(of: defaultTextEncoding) {
          AppPreferences.General.defaultTextEncoding = defaultTextEncoding
        }
        .formMenuPicker()

        Picker(Localized.Settings.defaultLineEndings, selection: $defaultLineEndings) {
          Text(Localized.Settings.macOSLineEndings).tag(LineEndings.lf)
          Text(Localized.Settings.windowsLineEndings).tag(LineEndings.crlf)
          Text(Localized.Settings.classicMacLineEndings).tag(LineEndings.cr)
        }
        .onChange(of: defaultLineEndings) {
          AppPreferences.General.defaultLineEndings = defaultLineEndings
        }
        .formMenuPicker()
      }

      Section {
        Picker(Localized.Settings.tabbingMode, selection: $tabbingMode) {
          Text(Localized.Settings.automatic).tag(NSWindow.TabbingMode.automatic)
          Text(Localized.Settings.preferred).tag(NSWindow.TabbingMode.preferred)
          Text(Localized.Settings.disallowed).tag(NSWindow.TabbingMode.disallowed)
        }
        .onChange(of: tabbingMode) {
          AppPreferences.Window.tabbingMode = tabbingMode
        }
        .formMenuPicker()

        Toggle(Localized.Settings.reduceTransparencyDescription, isOn: $reduceTransparency)
          .onChange(of: reduceTransparency) {
            AppPreferences.Window.reduceTransparency = reduceTransparency
          }
          .formLabel(Localized.Settings.reduceTransparencyLabel)
      }

      Section {
        HStack {
          Text(sidebarRootPath ?? "Current document's folder")
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            // The form window sizes to its widest row; a long path must not win
            .frame(maxWidth: 224, alignment: .leading)

          Button("Choose…") {
            Task {
              await NSApp.appDelegate?.saveSidebarRootBookmark()
              sidebarRootPath = Self.resolvedSidebarRootPath()
            }
          }

          if sidebarRootPath != nil {
            Button("Reset") {
              AppPreferences.General.sidebarRootBookmark = nil
              sidebarRootPath = nil

              for editor in EditorPreloader.shared.viewControllers() {
                editor.reloadSidebar()
              }
            }
          }
        }
        .formLabel("Sidebar folder")
      }
    }
  }

  private static func resolvedSidebarRootPath() -> String? {
    guard var path = AppDelegate.resolvedSidebarRootURL()?.path else {
      return nil
    }

    // abbreviatingWithTildeInPath resolves to the sandbox container, not the real home
    if let home = NSHomeDirectoryForUser(NSUserName()), path.hasPrefix(home) {
      path = "~" + path.dropFirst(home.count)
    }

    return path
  }
}
