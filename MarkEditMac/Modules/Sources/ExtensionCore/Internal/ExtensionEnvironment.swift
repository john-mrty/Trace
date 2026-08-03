//
//  ExtensionEnvironment.swift
//
//  Created by cyan on 7/12/26.
//

import Foundation
import AppKitExtensions
import MarkEditKit

/// Injectable environment for ExtensionCore: filesystem locations.
///
/// Defaults match the sandboxed app; tests can point these at temporary directories.
enum ExtensionEnvironment {
  /// Base directory holding extensions.json and the scripts/ folder.
  nonisolated(unsafe) static var documentsDirectory = URL.documentsDirectory

  static var extensionsURL: URL {
    documentsDirectory
      .appending(path: "extensions.json", directoryHint: .notDirectory)
      .resolvingSymbolicLink
  }

  static var scriptsDirectory: URL {
    documentsDirectory
      .appending(path: "scripts", directoryHint: .isDirectory)
      .resolvingSymbolicLink
  }
}
