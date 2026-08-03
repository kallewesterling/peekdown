import Foundation

enum MarkdownRenderer {

    enum RenderError: Error {
        case missingResource(String)
        case unreadableFile
    }

    static func renderHTML(forFileAt url: URL) throws -> String {
        let markdownText = try readText(at: url)
        let inlinedMarkdown = inlineLocalImages(in: markdownText, relativeTo: url.deletingLastPathComponent())

        let bundle = Bundle(for: BundleToken.self)
        guard let templateURL = bundle.url(forResource: "template", withExtension: "html"),
              let markedJSURL = bundle.url(forResource: "marked.min", withExtension: "js"),
              let cssURL = bundle.url(forResource: "github-markdown", withExtension: "css") else {
            throw RenderError.missingResource("template/marked/css")
        }

        var html = try String(contentsOf: templateURL, encoding: .utf8)
        let markedJS = try String(contentsOf: markedJSURL, encoding: .utf8)
        let css = try String(contentsOf: cssURL, encoding: .utf8)

        html = html.replacingOccurrences(of: "/* __GITHUB_MARKDOWN_CSS__ */", with: css)
        html = html.replacingOccurrences(of: "/* __MARKED_JS__ */", with: markedJS)
        html = html.replacingOccurrences(of: "/* __MARKDOWN_SOURCE_JSON__ */", with: jsonStringLiteral(for: inlinedMarkdown))

        return html
    }

    /// Reads a text file, tolerating non-UTF8 encodings that show up in the wild.
    private static func readText(at url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf16, .isoLatin1, .windowsCP1252] {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        throw RenderError.unreadableFile
    }

    /// Encodes a Swift string as a JSON string literal, safe to embed inside a <script> tag.
    private static func jsonStringLiteral(for string: String) -> String {
        let data = try? JSONEncoder().encode(string)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        // Prevent an embedded "</script>" from prematurely closing our <script> tag.
        return json.replacingOccurrences(of: "</", with: "<\\/")
    }

    /// Rewrites relative image references (![alt](path)) into inline base64 data URIs
    /// so the preview stays self-contained regardless of sandbox file access.
    private static func inlineLocalImages(in markdown: String, relativeTo directory: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)\s]+)([^)]*)\)"#) else {
            return markdown
        }
        let nsMarkdown = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))

        var result = markdown
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let pathRange = match.range(at: 2)
            let path = nsMarkdown.substring(with: pathRange)

            guard let dataURI = dataURI(forImagePath: path, relativeTo: directory) else { continue }

            let fullRange = match.range(at: 0)
            let altRange = match.range(at: 1)
            let alt = nsMarkdown.substring(with: altRange)
            let replacement = "![\(alt)](\(dataURI))"

            if let swiftRange = Range(fullRange, in: result) {
                result.replaceSubrange(swiftRange, with: replacement)
            }
        }
        return result
    }

    private static func dataURI(forImagePath path: String, relativeTo directory: URL) -> String? {
        guard let unescaped = path.removingPercentEncoding ?? Optional(path) else { return nil }
        guard !unescaped.hasPrefix("http://"), !unescaped.hasPrefix("https://"), !unescaped.hasPrefix("data:") else {
            return nil
        }

        let fileURL: URL
        if unescaped.hasPrefix("file://") {
            guard let u = URL(string: unescaped) else { return nil }
            fileURL = u
        } else if unescaped.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: unescaped)
        } else {
            fileURL = directory.appendingPathComponent(unescaped)
        }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let mime = mimeType(forExtension: fileURL.pathExtension.lowercased())
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        default: return "application/octet-stream"
        }
    }
}

private final class BundleToken {}
