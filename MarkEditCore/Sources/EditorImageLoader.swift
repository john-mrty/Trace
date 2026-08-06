//
//  EditorImageLoader.swift
//
//  Created by cyan on 5/29/25.
//

import WebKit
import UniformTypeIdentifiers
import os.log

/// URL scheme handler to load local images.
///
/// E.g., image-loader://Image.png
public final class EditorImageLoader: NSObject, WKURLSchemeHandler {
  public static let scheme = "image-loader"
  private let getBaseURL: () -> URL?

  public init(getBaseURL: @escaping () -> URL?) {
    self.getBaseURL = getBaseURL
  }

  public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard let url = urlSchemeTask.request.url else {
      urlSchemeTask.didFailWithError(URLError(.badURL))
      return assertionFailure("Invalid url scheme task")
    }

    // The path travels in ?src= because URL normalization would collapse
    // "../" segments in the path slot; queryItems percent-decodes once,
    // then the source's own Markdown-level encoding is decoded below
    let rawPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?
      .first { $0.name == "src" }?
      .value ?? url.absoluteString.replacingOccurrences(of: "\(Self.scheme)://", with: "")

    let path = rawPath.removingPercentEncoding ?? rawPath
    let fileURL: URL? = {
      if path.hasPrefix("/") {
        return URL(filePath: path, directoryHint: .notDirectory)
      }

      return getBaseURL()?.appending(path: path, directoryHint: .notDirectory)
    }()

    if let fileURL, let fileData = try? Data(contentsOf: fileURL) {
      let response = URLResponse(
        url: url,
        mimeType: UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType,
        expectedContentLength: fileData.count,
        textEncodingName: nil
      )

      urlSchemeTask.didReceive(response)
      urlSchemeTask.didReceive(fileData)
      urlSchemeTask.didFinish()
    } else {
      os_logger.log(level: .error, "Failed to load image: \(fileURL?.path ?? url.absoluteString, privacy: .public)")

      let response = HTTPURLResponse(
        url: url,
        statusCode: 404,
        httpVersion: nil,
        headerFields: nil
      )

      if let response {
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didFinish()
      } else {
        urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        assertionFailure("Failed to create 404 response")
      }
    }
  }

  public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    // no-op
  }
}

private let os_logger = os.Logger()
