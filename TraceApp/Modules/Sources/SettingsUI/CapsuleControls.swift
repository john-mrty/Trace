//
//  CapsuleControls.swift
//
//  Created by cyan on 8/12/26.
//

import SwiftUI

/**
 Full-radius select: a Menu styled as a capsule (matching the find bar), with
 an inline Picker inside so options keep native checkmarks. The caller renders
 the current value via `currentLabel` since Menu can't read Picker state.
 */
public struct CapsuleMenu<SelectionValue: Hashable, Content: View, CurrentLabel: View>: View {
  @Binding private var selection: SelectionValue
  private let minWidth: Double
  private let content: () -> Content
  private let currentLabel: () -> CurrentLabel

  public init(
    selection: Binding<SelectionValue>,
    minWidth: Double = 280,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder currentLabel: @escaping () -> CurrentLabel
  ) {
    self._selection = selection
    self.minWidth = minWidth
    self.content = content
    self.currentLabel = currentLabel
  }

  public var body: some View {
    Menu {
      Picker(selection: $selection) {
        content()
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      HStack {
        currentLabel()
        Spacer()
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity)
      .contentShape(Capsule())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    // minWidth on the outer frame keeps rows the same width as other 280pt rows
    .frame(minWidth: minWidth)
    .background(Capsule().fill(Color.primary.opacity(0.06)))
  }
}

/**
 Full-radius push button, matching the find bar's "Done" capsule.
 */
public struct CapsuleButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 5)
      .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06)))
      .contentShape(Capsule())
  }
}
