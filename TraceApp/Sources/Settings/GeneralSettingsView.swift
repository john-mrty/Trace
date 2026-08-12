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
  @State private var reduceTransparency = AppPreferences.Window.reduceTransparency
  @State private var sidebarRootPath = Self.resolvedSidebarRootPath()

  var body: some View {
    SettingsForm {
      Section {
        CapsuleMenu(selection: $newWindowBehavior) {
          Text(Localized.Document.openDocument).tag(NewWindowBehavior.openDocument)
          Text(Localized.Document.newDocument).tag(NewWindowBehavior.newDocument)
        } currentLabel: {
          Text(newWindowBehavior == .openDocument ? Localized.Document.openDocument : Localized.Document.newDocument)
        }
        .onChange(of: newWindowBehavior) {
          AppPreferences.General.newWindowBehavior = newWindowBehavior
        }
        .formLabel(Localized.Settings.newWindowBehavior)

        Toggle(Localized.Settings.quitAlwaysKeepsWindows, isOn: $quitAlwaysKeepsWindows)
          .onChange(of: quitAlwaysKeepsWindows) {
            AppPreferences.General.quitAlwaysKeepsWindows = quitAlwaysKeepsWindows
          }
          .formLabel(Localized.Settings.windowRestoration)
          .formBreathingInset()
      }

      Section {
        CapsuleMenu(selection: $newFilenameExtension) {
          ForEach(NewFilenameExtension.allCases, id: \.self) {
            Text($0.rawValue).tag($0)
          }
        } currentLabel: {
          Text(newFilenameExtension.rawValue)
        }
        .onChange(of: newFilenameExtension) {
          AppPreferences.General.newFilenameExtension = newFilenameExtension
        }
        .formLabel(Localized.Settings.newFilenameExtension)

        CapsuleMenu(selection: $defaultTextEncoding) {
          ForEach(EditorTextEncoding.allCases, id: \.self) {
            Text($0.description)

            if EditorTextEncoding.groupingCases.contains($0) {
              Divider()
            }
          }
        } currentLabel: {
          Text(defaultTextEncoding.description)
        }
        .onChange(of: defaultTextEncoding) {
          AppPreferences.General.defaultTextEncoding = defaultTextEncoding
        }
        .formLabel(Localized.Settings.defaultTextEncoding)

        CapsuleMenu(selection: $defaultLineEndings) {
          Text(Localized.Settings.macOSLineEndings).tag(LineEndings.lf)
          Text(Localized.Settings.windowsLineEndings).tag(LineEndings.crlf)
          Text(Localized.Settings.classicMacLineEndings).tag(LineEndings.cr)
        } currentLabel: {
          Text(lineEndingsName(defaultLineEndings))
        }
        .onChange(of: defaultLineEndings) {
          AppPreferences.General.defaultLineEndings = defaultLineEndings
        }
        .formLabel(Localized.Settings.defaultLineEndings)
      }

      Section {
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
            .frame(maxWidth: .infinity, alignment: .leading)

          Button("Choose…") {
            Task {
              await NSApp.appDelegate?.saveSidebarRootBookmark()
              sidebarRootPath = Self.resolvedSidebarRootPath()
            }
          }
          .buttonStyle(CapsuleButtonStyle())

          if sidebarRootPath != nil {
            Button("Reset") {
              AppPreferences.General.sidebarRootBookmark = nil
              sidebarRootPath = nil

              for editor in EditorPreloader.shared.viewControllers() {
                editor.reloadSidebar()
              }
            }
            .buttonStyle(CapsuleButtonStyle())
          }
        }
        // Same width as formMenuPicker rows, so this row never widens the form
        .frame(width: 280)
        .formLabel("Sidebar folder")
      }
    }
  }

  private func lineEndingsName(_ value: LineEndings) -> String {
    switch value {
    case .crlf:
      return Localized.Settings.windowsLineEndings
    case .cr:
      return Localized.Settings.classicMacLineEndings
    default:
      return Localized.Settings.macOSLineEndings
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
