//
//  SettingsTabSwitcher.swift
//
//  Created by cyan on 8/12/26.
//

import SwiftUI

@MainActor
final class SettingsTabSelection: ObservableObject {
  @Published var index = 0
}

/**
 Capsule-style tab switcher: grey pill track, the selected segment floats as a
 white capsule with a soft shadow, icons sit inline with the labels.
 */
struct SettingsTabSwitcher: View {
  struct Item {
    let title: String
    let icon: String
  }

  let items: [Item]
  let onSelect: (Int) -> Void
  @ObservedObject var selection: SettingsTabSelection

  var body: some View {
    HStack(spacing: 0) {
      ForEach(items.indices, id: \.self) { index in
        segment(at: index)
      }
    }
    .padding(3)
    .background(Capsule().fill(Color.primary.opacity(0.06)))
    // Room for the selected capsule's shadow; the hosting view clips at its bounds
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
  }

  private func segment(at index: Int) -> some View {
    let isSelected = index == selection.index
    return Button {
      onSelect(index)
    } label: {
      HStack(spacing: 5) {
        Image(systemName: items[index].icon)
          .font(.system(size: 11, weight: .semibold))
        Text(items[index].title)
          .font(.system(size: 13, weight: .medium))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .foregroundStyle(isSelected ? Color.primary : Color.secondary)
      .background {
        if isSelected {
          Capsule()
            .fill(Color(nsColor: .windowBackgroundColor))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .animation(.easeInOut(duration: 0.15), value: selection.index)
  }
}
