//
//  EditorOverlayGeometry.swift
//
//  Created by cyan on 8/2/26.
//

import AppKit

/// Pure geometry for the right-edge overlay window. No side effects; unit-tested.
public enum EditorOverlayGeometry {
  /// A rect flush to the right of `visibleFrame`, full height,
  /// `widthFraction` of the visible width.
  public static func frame(in visibleFrame: NSRect, widthFraction: CGFloat) -> NSRect {
    let width = (visibleFrame.width * widthFraction).rounded()
    return NSRect(
      x: visibleFrame.maxX - width,
      y: visibleFrame.minY,
      width: width,
      height: visibleFrame.height
    )
  }

  /// Same size, parked just off the right screen edge (start of the slide-in).
  public static func offscreenFrame(in visibleFrame: NSRect, widthFraction: CGFloat) -> NSRect {
    var frame = frame(in: visibleFrame, widthFraction: widthFraction)
    frame.origin.x = visibleFrame.maxX
    return frame
  }
}
