//
//  StatisticsCell.swift
//
//  Created by cyan on 8/26/23.
//

import SwiftUI

struct StatisticsCell: View {
  static let cellHeight: Double = 26
  static let rowHeight: Double = cellHeight

  let titleText: String
  let valueText: String

  var body: some View {
    HStack {
      Text(titleText)
        .fixedSize()
      Spacer()
      Text(valueText)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .font(.system(size: 13))
    .padding(.horizontal, 10)
    .accessibilityElement()
    .accessibilityLabel([titleText, valueText].joined(separator: " "))
    .frame(height: Self.cellHeight)
  }
}
