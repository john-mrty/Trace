//
//  EditorOverlayGeometryTests.swift
//
//  Created by cyan on 8/2/26.
//

import XCTest
import AppKit
import AppKitExtensions

final class EditorOverlayGeometryTests: XCTestCase {
  func testFrameIsFlushToRightEdgeFullHeight() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = EditorOverlayGeometry.frame(in: visible, widthFraction: 1.0 / 3.0)
    XCTAssertEqual(frame.width, 480, accuracy: 0.5)   // 1440 / 3
    XCTAssertEqual(frame.height, 900, accuracy: 0.5)  // full visible height
    XCTAssertEqual(frame.maxX, visible.maxX, accuracy: 0.5) // flush right
    XCTAssertEqual(frame.minY, visible.minY, accuracy: 0.5)
  }

  func testOffscreenFrameIsParkedAtRightEdge() {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = EditorOverlayGeometry.offscreenFrame(in: visible, widthFraction: 1.0 / 3.0)
    XCTAssertEqual(frame.minX, visible.maxX, accuracy: 0.5)
    XCTAssertEqual(frame.width, 480, accuracy: 0.5)
    XCTAssertEqual(frame.height, 900, accuracy: 0.5)
  }
}
