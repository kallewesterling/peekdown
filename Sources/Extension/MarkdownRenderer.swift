import Foundation
import UniformTypeIdentifiers

enum MarkdownRenderer {

    enum RenderError: Error {
        case missingResource(String)
        case unreadableFile
    }

    /// Guard rails so that previewing a pathological file can't wedge Quick Look.
    /// Everything is inlined into a single HTML string held in memory, so an
    /// unbounded document or image turns into an unbounded allocation.
    private enum Limits {
        /// Largest Markdown source we'll render; beyond this the text is truncated.
        static let markdownBytes = 4 * 1024 * 1024
        /// Largest single image we'll base64-inline.
        static let imageBytes = 8 * 1024 * 1024
        /// Total image budget for one preview.
        static let totalImageBytes = 32 * 1024 * 1024
    }

    static func renderHTML(forFileAt url: URL) throws -> String {
        let markdownText = try readText(at: url)
        let (clamped, wasTruncated) = truncateIfNeeded(markdownText)
        var source = inlineLocalImages(in: clamped, relativeTo: url.deletingLastPathComponent())
        if wasTruncated {
            source += "\n\n---\n\n*Preview truncated — this file is larger than "
                + "\(Limits.markdownBytes / (1024 * 1024)) MB.*\n"
        }

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
        html = html.replacingOccurrences(of: "/* __MARKDOWN_SOURCE_JSON__ */", with: jsonStringLiteral(for: source))

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

    private static func truncateIfNeeded(_ text: String) -> (String, Bool) {
        guard text.utf8.count > Limits.markdownBytes else { return (text, false) }
        let prefix = String(decoding: text.utf8.prefix(Limits.markdownBytes), as: UTF8.self)
        return (prefix, true)
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
    ///
    /// Image syntax inside code spans and fenced code blocks is left alone — a
    /// document *about* Markdown should show `![logo](logo.png)`, not a base64 blob.
    private static func inlineLocalImages(in markdown: String, relativeTo directory: URL) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)\s]+)([^)]*)\)"#) else {
            return markdown
        }
        let nsMarkdown = markdown as NSString
        let wholeRange = NSRange(location: 0, length: nsMarkdown.length)
        let matches = regex.matches(in: markdown, range: wholeRange)
        let codeRanges = codeRegions(in: markdown)

        var result = markdown
        var budget = Limits.totalImageBytes

        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let matchRange = match.range(at: 0)
            // Skip anything that lives inside a code span or fenced code block.
            if codeRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) { continue }

            let path = nsMarkdown.substring(with: match.range(at: 2))
            guard let dataURI = dataURI(forImagePath: path, relativeTo: directory, budget: &budget) else { continue }

            let alt = nsMarkdown.substring(with: match.range(at: 1))
            let replacement = "![\(alt)](\(dataURI))"

            if let swiftRange = Range(matchRange, in: result) {
                result.replaceSubrange(swiftRange, with: replacement)
            }
        }
        return result
    }

    /// Ranges covered by fenced code blocks (``` / ~~~) and inline code spans (`…`).
    private static func codeRegions(in markdown: String) -> [NSRange] {
        let patterns = [
            // Fenced blocks: an opening run of >=3 backticks/tildes through the
            // matching closing run, or end of document if it is never closed.
            #"(?m)^[ \t]{0,3}(`{3,}|~{3,})[^\n]*$[\s\S]*?(?:^[ \t]{0,3}\1[ \t]*$|\z)"#,
            // Inline spans: a run of backticks through the next run of equal length.
            #"(`+)(?:[^`]|(?!\1)`)*?\1"#,
        ]
        let range = NSRange(location: 0, length: (markdown as NSString).length)
        return patterns.flatMap { pattern -> [NSRange] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: markdown, range: range).map { $0.range }
        }
    }

    private static func dataURI(forImagePath path: String, relativeTo directory: URL, budget: inout Int) -> String? {
        let unescaped = path.removingPercentEncoding ?? path
        guard !isRemote(unescaped) else { return nil }

        let fileURL: URL
        if unescaped.lowercased().hasPrefix("file://") {
            guard let u = URL(string: unescaped), u.isFileURL else { return nil }
            fileURL = u
        } else if unescaped.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: unescaped)
        } else {
            fileURL = directory.appendingPathComponent(unescaped)
        }

        // Only inline things the WebView can actually display, and check the size
        // before reading so a huge file is never pulled into memory at all.
        guard let mime = imageMIMEType(for: fileURL),
              let size = fileSize(of: fileURL),
              size <= Limits.imageBytes,
              size <= budget,
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            return nil
        }

        budget -= data.count
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    /// True for anything that should be fetched over the network rather than inlined,
    /// or that must never be treated as a file path. Case-insensitive, and
    /// protocol-relative ("//host/x.png") counts as remote.
    private static func isRemote(_ path: String) -> Bool {
        if path.hasPrefix("//") { return true }
        let lowered = path.lowercased()
        return ["http://", "https://", "data:", "about:", "javascript:"].contains { lowered.hasPrefix($0) }
    }

    private static func fileSize(of url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// Resolves an image MIME type from the file extension, returning nil for anything
    /// that isn't an image. Previously unknown extensions were inlined as
    /// application/octet-stream, which no browser renders.
    private static func imageMIMEType(for url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()),
              type.conforms(to: .image),
              let mime = type.preferredMIMEType else {
            return nil
        }
        return mime
    }
}

private final class BundleToken {}
