import Foundation

/// JSON as text: written out again in the backbone's own key order (`JSONSerialization` would reorder it), with the
/// size hints a structured answer carries.
enum JSONText {
    /// `json`, already known to parse, written out as `layout` says. Strings and numbers stay exactly as the backbone
    /// wrote them; only the whitespace between tokens changes.
    static func format(_ json: String, layout: JSONLayout) -> String {
        var out = String.UnicodeScalarView()
        let scalars = Array(json.unicodeScalars)
        var inString = false, escaped = false, depth = 0
        func newline(_ level: Int) {
            out.append("\n")
            out.append(contentsOf: String(repeating: "  ", count: level).unicodeScalars)
        }
        /// The next scalar after `i` that isn't whitespace.
        func next(after i: Int) -> Unicode.Scalar? {
            var j = i + 1
            while j < scalars.count, isWhitespace(scalars[j]) { j += 1 }
            return j < scalars.count ? scalars[j] : nil
        }
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            defer { i += 1 }
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if isWhitespace(c) { continue }
            switch (c, layout) {
            case ("\"", _):
                inString = true
                out.append(c)
            case ("{", .pretty), ("[", .pretty):
                out.append(c)
                let close: Unicode.Scalar = c == "{" ? "}" : "]"
                if next(after: i) == close {
                    out.append(close)                     // `{}` and `[]` stay on one line, as Python writes them
                    while i + 1 < scalars.count, scalars[i + 1] != close { i += 1 }
                    i += 1
                } else {
                    depth += 1
                    newline(depth)
                }
            case ("}", .pretty), ("]", .pretty):
                depth = max(0, depth - 1)
                newline(depth)
                out.append(c)
            case (",", .pretty):
                out.append(c)
                newline(depth)
            case (":", .pretty):
                out.append(contentsOf: ": ".unicodeScalars)
            default:
                out.append(c)
            }
        }
        return String(out)
    }

    private static func isWhitespace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\n" || c == "\r" || c == "\t" }

    /// The JSON value in `text`: the whole text, or else the span from its first `{` to its last `}` (a backbone that
    /// wrote a sentence around its object). Returns the span and its parsed value.
    static func extract(_ text: String) -> (json: String, value: Any)? {
        if let value = parse(text) { return (text, value) }
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        let span = String(text[open...close])
        return parse(span).map { (span, $0) }
    }

    private static func parse(_ text: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }

    /// The string (or number) at `path` in `value`.
    static func scalar(at path: [String], in value: Any) -> String? {
        var current: Any? = value
        for key in path { current = (current as? [String: Any])?[key] }
        if let string = current as? String { return string }
        if let number = current as? NSNumber { return number.stringValue }
        return nil
    }

    /// A size read from text such as `"2048 x 2048"`, `"16:9"` or `"1:1, 2048 × 2048 px"`.
    static func size(in text: String) -> SuggestedSize? {
        var size = SuggestedSize()
        if let m = text.firstMatch(of: /(\d{2,5})\s*[x×X*]\s*(\d{2,5})/), let w = Int(m.1), let h = Int(m.2), w > 0, h > 0 {
            size.width = w
            size.height = h
        }
        if let m = text.firstMatch(of: /(?:^|[^\d.])(\d{1,3}(?:\.\d+)?)\s*:\s*(\d{1,3}(?:\.\d+)?)(?![\d.])/),
           let a = Double(m.1), let b = Double(m.2), a > 0, b > 0 {
            size.aspectRatio = "\(m.1):\(m.2)"
        }
        return size.isEmpty ? nil : size
    }
}

/// The size a structured answer suggests for the image (`EnhanceProfile.sizeFields`): its width and height when it
/// names them, and its aspect ratio as written. A host may use it when the request named no size; the kit doesn't
/// snap it to any model's grid.
public struct SuggestedSize: Sendable, Equatable {
    public var width: Int?
    public var height: Int?
    /// `W:H` as the answer wrote it, e.g. `16:9`.
    public var aspectRatio: String?

    public init(width: Int? = nil, height: Int? = nil, aspectRatio: String? = nil) {
        self.width = width; self.height = height; self.aspectRatio = aspectRatio
    }

    var isEmpty: Bool { width == nil && height == nil && aspectRatio == nil }

    /// The ratio as a number (width over height): from `aspectRatio`, or else from `width` and `height`.
    public var ratio: Double? {
        if let aspect = aspectRatio {
            let parts = aspect.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 { return parts[0] / parts[1] }
        }
        if let width, let height, height > 0 { return Double(width) / Double(height) }
        return nil
    }

    /// `other`'s values where this has none.
    func filling(from other: SuggestedSize) -> SuggestedSize {
        SuggestedSize(width: width ?? other.width, height: height ?? other.height, aspectRatio: aspectRatio ?? other.aspectRatio)
    }
}
