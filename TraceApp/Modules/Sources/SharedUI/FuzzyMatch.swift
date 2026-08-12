//
//  FuzzyMatch.swift
//
//  Created by cyan on 8/12/26.
//

import Foundation

enum FuzzyMatch {
  /// Case-insensitive subsequence match, higher is better, nil means no match.
  /// Contiguous matches beat scattered ones ("h2" hits both "Header 2" and "H2").
  static func score(query: String, in text: String) -> Int? {
    let query = Array(query.lowercased())
    let text = Array(text.lowercased())

    if let range = text.firstRange(of: query) {
      return 1000 - range.lowerBound
    }

    var score = 500
    var textIndex = 0

    for char in query {
      var found = false
      while textIndex < text.count {
        if text[textIndex] == char {
          found = true
          textIndex += 1
          break
        }

        score -= 1
        textIndex += 1
      }

      if !found {
        return nil
      }
    }

    return score
  }
}
