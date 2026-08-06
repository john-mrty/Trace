//
//  StatisticsView.swift
//
//  Created by cyan on 8/26/23.
//

import AppKit
import AppKitExtensions
import SwiftUI

struct StatisticsView: View {
  private let modernStyle: Bool
  private let fullResult: StatisticsResult
  private let selectionResult: StatisticsResult?
  private let fullRuleResults: [StatisticsRuleResult]
  private let selectionRuleResults: [StatisticsRuleResult]?
  private let fileURL: URL?
  private let localizable: StatisticsLocalizable

  @State private var viewingMode: ViewingMode = .selection
  @State private var localMonitor: Any?

  init(
    modernStyle: Bool,
    fullResult: StatisticsResult,
    selectionResult: StatisticsResult?,
    fullRuleResults: [StatisticsRuleResult] = [],
    selectionRuleResults: [StatisticsRuleResult]? = nil,
    fileURL: URL?,
    localizable: StatisticsLocalizable
  ) {
    self.modernStyle = modernStyle
    self.fullResult = fullResult
    self.selectionResult = selectionResult
    self.fullRuleResults = fullRuleResults
    self.selectionRuleResults = selectionRuleResults
    self.fileURL = fileURL
    self.localizable = localizable
  }

  var body: some View {
    VStack(spacing: 0) {
      if selectionResult != nil {
        Picker(localizable.mainTitle, selection: $viewingMode) {
          Text(localizable.selection).tag(ViewingMode.selection)
          Text(localizable.document).tag(ViewingMode.document)
        }
        .labelsHidden() // Hide the label while keeping the accessibility
        .pickerStyle(.segmented)
        .padding(.horizontal, 10)
        .frame(height: modernStyle ? 40 : 36)
        .onAppear {
          localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case .kVK_LeftArrow:
              viewingMode = .selection
              return nil
            case .kVK_RightArrow:
              viewingMode = .document
              return nil
            default:
              return event
            }
          }
        }
        .onDisappear {
          if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
          }
        }
      }

      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(currentRuleResults.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, ruleResult in
            StatisticsCell(
              titleText: ruleResult.rule.title,
              valueText: "\(ruleResult.count)"
            )
          }

          StatisticsCell(
            titleText: localizable.characters,
            valueText: "\(currentResult.characters)"
          )

          StatisticsCell(
            titleText: localizable.words,
            valueText: "\(currentResult.words)"
          )

          StatisticsCell(
            titleText: localizable.sentences,
            valueText: "\(currentResult.sentences)"
          )

          StatisticsCell(
            titleText: localizable.paragraphs,
            valueText: "\(currentResult.paragraphs)"
          )

          if currentResult.comments > 0 {
            StatisticsCell(
              titleText: localizable.comments,
              valueText: "\(currentResult.comments)"
            )
          }

          if let readTime = ReadTime.estimated(of: currentResult.words) {
            StatisticsCell(
              titleText: localizable.readTime,
              valueText: readTime
            )
          }

          // The file size is shown only when we are viewing the full document
          if isViewingDocument, let fileSize = FileSize.readableSize(of: fileURL) {
            StatisticsCell(
              titleText: localizable.fileSize,
              valueText: fileSize
            )
          }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
      }
    }
  }
}

// MARK: - Private

private extension StatisticsView {
  enum ViewingMode: Int {
    case selection = 0
    case document = 1
  }

  var isViewingDocument: Bool {
    // We are viewing full document if there's no selection, or we explicitly selected the document section
    selectionResult == nil || viewingMode == .document
  }

  var currentResult: StatisticsResult {
    if !isViewingDocument, let selectionResult {
      return selectionResult
    }

    return fullResult
  }

  var currentRuleResults: [StatisticsRuleResult] {
    if !isViewingDocument, let selectionRuleResults {
      return selectionRuleResults
    }

    return fullRuleResults
  }
}
