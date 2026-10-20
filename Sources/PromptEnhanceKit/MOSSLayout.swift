import Foundation

/// MOSS-Image's prompt compiler, ported from its prompt-enhancer skill's `scripts/compile_prompt.py`
/// (github.com/OpenMOSS/MOSS-Image @ 6f9aabb9db61576838287a18b046383b5402fe26, Apache-2.0; see THIRD-PARTY-NOTICES.md).
/// The skill has an agent write a draft and run this script on it; here the backbone writes the draft and the kit runs
/// the port (`AnswerCompiler.mossImageLayout`).
///
/// - A caption draft, exactly `{"caption": "…"}`, becomes its caption.
/// - A Layout draft (exactly `width`, `height`, `bbox_coord_space: "abs"`, `bbox_format: "xyxy"`, `summary` and `items`,
///   with `[x1, y1, x2, y2]` boxes in pixels from the canvas's top-left) becomes the one-line JSON the model reads:
///   `{"summary", "items", "bbox_coord_space": "abs_centralized", "bbox_format": "yxyx"}`, with no canvas. Each box is
///   enclosed in whole pixels (top and left floored, bottom and right ceiled, after rounding to nine decimals) and then
///   centred (H/2 subtracted from y, W/2 from x), in `yxyx` order. Everything else keeps the draft's text and key order.
/// - A draft the script rejects is rejected, with the script's message: unknown or missing fields, a label other than
///   `object`, `character` or `text`, a text item without its literal, a box outside the canvas or empty at export
///   precision, a side that isn't a positive multiple of 16, a duplicate key, a non-finite number.
///
/// Changed in the port: the script reads a file and writes one; this reads the backbone's answer (the whole text, or
/// else its first `{` to its last `}`, as the kit reads every JSON answer) and returns the prompt with the draft's
/// canvas. Python's `json.dumps(..., ensure_ascii=False, separators=(",", ":"))` is reproduced by `write`.
enum MOSSLayout {
    struct Compiled: Equatable {
        var prompt: String
        /// The Layout draft's `width` and `height`; nil for a caption.
        var canvas: CanvasSize?
    }

    /// A draft the script would reject; `description` is its message.
    struct Invalid: Error, CustomStringConvertible, Equatable {
        let description: String
    }

    static func compile(_ answer: String) throws -> Compiled {
        let draft: JSONValue
        if let whole = try? JSONValue.parse(answer) {
            draft = whole
        } else if let open = answer.firstIndex(of: "{"), let close = answer.lastIndex(of: "}"), open < close {
            draft = try JSONValue.parse(String(answer[open...close]))
        } else {
            throw Invalid(description: "The answer isn't JSON: \(answer.prefix(120))")
        }
        return try compile(draft)
    }

    /// `compile_prompt(draft)`.
    static func compile(_ draft: JSONValue) throws -> Compiled {
        guard case .object(let root) = draft else { throw Invalid(description: "Draft must be a JSON object") }
        if root.contains(where: { $0.key == "caption" }) {
            try fields(draft, allowed: ["caption"], required: ["caption"], "Caption draft")
            let caption = try text(draft["caption"], "caption")
            return Compiled(prompt: caption, canvas: nil)
        }

        let rootFields: Set<String> = ["width", "height", "bbox_coord_space", "bbox_format", "summary", "items"]
        try fields(draft, allowed: rootFields, required: rootFields, "Layout draft")
        var sides: [Int] = []
        for name in ["width", "height"] {
            guard case .number(let lexeme, let value)? = draft[name], JSONValue.isInteger(lexeme), value > 0,
                  let side = Int(exactly: value), side % 16 == 0 else {
                throw Invalid(description: "\(name) must be a positive integer multiple of 16")
            }
            sides.append(side)
        }
        let (width, height) = (sides[0], sides[1])
        guard draft["bbox_coord_space"] == .string("abs") else {
            throw Invalid(description: "Draft bbox_coord_space must be abs")
        }
        guard draft["bbox_format"] == .string("xyxy") else { throw Invalid(description: "Draft bbox_format must be xyxy") }

        let summary = draft["summary"]!
        try fields(summary, allowed: ["caption", "meta", "canvas", "palette"], required: ["caption"], "summary")
        _ = try text(summary["caption"], "summary.caption")
        let canvases: [JSONValue] = [.string("single"), .string("multi_panel"), .string("collage")]
        if let canvas = summary["canvas"], !canvases.contains(canvas) {
            throw Invalid(description: "summary.canvas must be single, multi_panel or collage")
        }
        for key in ["meta", "palette"] {
            if let value = summary[key] { try strings(value, "summary.\(key)") }
        }

        guard case .array(let items) = draft["items"]!, !items.isEmpty else {
            throw Invalid(description: "items must be a nonempty flat array")
        }
        var compiledItems: [JSONValue] = []
        for (index, item) in items.enumerated() {
            let location = "items[\(index)]"
            try fields(item, allowed: ["label", "caption", "bbox", "text", "tags", "palette"],
                       required: ["label", "caption", "bbox"], location)
            guard [.string("object"), .string("character"), .string("text")].contains(item["label"]!) else {
                throw Invalid(description: "\(location).label must be object, character or text")
            }
            _ = try text(item["caption"], "\(location).caption")
            if item["label"] == .string("text"), item["text"] == nil {
                throw Invalid(description: "\(location): text items require literal text")
            }
            if let literal = item["text"] { _ = try text(literal, "\(location).text") }
            for key in ["tags", "palette"] {
                if let value = item[key] { try strings(value, "\(location).\(key)") }
            }
            guard case .object(let members) = item else { continue }
            compiledItems.append(.object(try members.map { member in
                guard member.key == "bbox" else { return member }
                let box = try centeredBox(member.value, width: width, height: height, "\(location).bbox")
                return (member.key, .array(box.map { .number(String($0), Double($0)) }))
            }))
        }

        let result = JSONValue.object([("summary", summary), ("items", .array(compiledItems)),
                                       ("bbox_coord_space", .string("abs_centralized")), ("bbox_format", .string("yxyx"))])
        return Compiled(prompt: result.written, canvas: CanvasSize(width: width, height: height))
    }

    /// `centered_box(box, width, height, location)`: `[x1, y1, x2, y2]` in pixels → `[y1, x1, y2, x2]` enclosed in whole
    /// pixels and centred on the canvas.
    static func centeredBox(_ box: JSONValue, width: Int, height: Int, _ location: String) throws -> [Int] {
        guard case .array(let values) = box, values.count == 4 else {
            throw Invalid(description: "\(location) must be [x1,y1,x2,y2]")
        }
        let numbers = values.compactMap { value -> Double? in
            if case .number(_, let n) = value, n.isFinite { return n } else { return nil }
        }
        guard numbers.count == 4 else { throw Invalid(description: "\(location) must contain four finite numbers") }
        let (x1, y1, x2, y2) = (numbers[0], numbers[1], numbers[2], numbers[3])
        guard x1 < x2, y1 < y2 else { throw Invalid(description: "\(location) must have positive width and height") }
        guard 0 <= x1, x2 <= Double(width), 0 <= y1, y2 <= Double(height) else {
            throw Invalid(description: "\(location) exceeds the \(width)x\(height) canvas")
        }
        // Enclose in pixel edges before centering, as in Echidna generation export.
        func round9(_ v: Double) -> Double { (v * 1e9).rounded(.toNearestOrEven) / 1e9 }
        let result = [Int(round9(y1).rounded(.down)) - height / 2, Int(round9(x1).rounded(.down)) - width / 2,
                      Int(round9(y2).rounded(.up)) - height / 2, Int(round9(x2).rounded(.up)) - width / 2]
        guard result[0] < result[2], result[1] < result[3] else {
            throw Invalid(description: "\(location) is too small at export precision")
        }
        return result
    }

    /// `fields(value, allowed, required, location)`.
    private static func fields(_ value: JSONValue, allowed: Set<String>, required: Set<String>,
                               _ location: String) throws {
        guard case .object(let members) = value else { throw Invalid(description: "\(location) must be an object") }
        let keys = Set(members.map(\.key))
        let unknown = keys.subtracting(allowed), missing = required.subtracting(keys)
        guard unknown.isEmpty else { throw Invalid(description: "\(location): unknown fields \(pythonList(unknown))") }
        guard missing.isEmpty else { throw Invalid(description: "\(location): missing fields \(pythonList(missing))") }
    }

    /// `text(value, location)`: a string with something besides whitespace.
    private static func text(_ value: JSONValue?, _ location: String) throws -> String {
        guard case .string(let string)? = value, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Invalid(description: "\(location) must be nonempty text")
        }
        return string
    }

    /// `strings(value, location)`.
    private static func strings(_ value: JSONValue, _ location: String) throws {
        guard case .array(let items) = value else { throw Invalid(description: "\(location) must be an array") }
        for (index, item) in items.enumerated() { _ = try text(item, "\(location)[\(index)]") }
    }

    /// `sorted(names)` as Python prints a list of strings.
    private static func pythonList(_ names: Set<String>) -> String {
        "[" + names.sorted().map { "'\($0)'" }.joined(separator: ", ") + "]"
    }
}

/// A JSON value that keeps its objects' key order and its numbers' text, read the way Python's `json.loads` reads a
/// MOSS draft there (`object_pairs_hook` rejecting duplicate keys, `parse_constant` rejecting `NaN` and `Infinity`).
indirect enum JSONValue: Equatable {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    /// The number as written, and its value.
    case number(String, Double)
    case bool(Bool)
    case null

    static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.object(let x), .object(let y)):
            x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case (.array(let x), .array(let y)): x == y
        case (.string(let x), .string(let y)): x == y
        case (.number(_, let x), .number(_, let y)): x == y
        case (.bool(let x), .bool(let y)): x == y
        case (.null, .null): true
        default: false
        }
    }

    /// An object's member.
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    /// Whether a number's text is an integer literal (Python's `int`), not a float such as `1024.0` or `1e3`.
    static func isInteger(_ lexeme: String) -> Bool { !lexeme.contains { $0 == "." || $0 == "e" || $0 == "E" } }

    // MARK: - Reading

    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    static func parse(_ text: String) throws -> JSONValue {
        var parser = Parser(bytes: Array(text.utf8))
        parser.skipWhitespace()
        let value = try parser.value()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw ParseError(description: "Extra data at \(parser.index)") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        func fail(_ what: String) -> ParseError { ParseError(description: "\(what) at \(index)") }

        mutating func value() throws -> JSONValue {
            guard index < bytes.count else { throw fail("Expecting value") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try number()
            default: throw fail("Expecting value")    // NaN and Infinity included: the script rejects them
            }
        }

        mutating func literal(_ word: String) throws {
            let expected = Array(word.utf8)
            guard bytes.count - index >= expected.count, Array(bytes[index..<index + expected.count]) == expected else {
                throw fail("Expecting value")
            }
            index += expected.count
        }

        mutating func object() throws -> JSONValue {
            index += 1
            var members: [(key: String, value: JSONValue)] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail("Expecting property name") }
                let key = try string()
                guard !members.contains(where: { $0.key == key }) else {
                    throw MOSSLayout.Invalid(description: "Duplicate JSON key: \(key)")
                }
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("Expecting ':' delimiter") }
                index += 1
                skipWhitespace()
                members.append((key, try value()))
                skipWhitespace()
                guard index < bytes.count else { throw fail("Expecting ',' delimiter") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw fail("Expecting ',' delimiter")
            }
        }

        mutating func array() throws -> JSONValue {
            index += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try value())
                skipWhitespace()
                guard index < bytes.count else { throw fail("Expecting ',' delimiter") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw fail("Expecting ',' delimiter")
            }
        }

        /// A string, from its opening quote. Raw control characters are refused, as `json.loads` refuses them.
        mutating func string() throws -> String {
            index += 1
            var out: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                switch byte {
                case UInt8(ascii: "\""):
                    return String(decoding: out, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard index < bytes.count else { throw fail("Unterminated string") }
                    let escape = bytes[index]
                    index += 1
                    let simple: [UInt8: UInt8] = [UInt8(ascii: "\""): 0x22, UInt8(ascii: "\\"): 0x5C,
                                                  UInt8(ascii: "/"): 0x2F, UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C,
                                                  UInt8(ascii: "n"): 0x0A, UInt8(ascii: "r"): 0x0D, UInt8(ascii: "t"): 0x09]
                    if let replacement = simple[escape] { out.append(replacement); continue }
                    guard escape == UInt8(ascii: "u") else { throw fail("Invalid \\escape") }
                    var scalar = try hex4()
                    if (0xD800...0xDBFF).contains(scalar), bytes.count - index >= 6, bytes[index] == UInt8(ascii: "\\"),
                       bytes[index + 1] == UInt8(ascii: "u") {
                        let save = index
                        index += 2
                        let low = try hex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            index = save
                        }
                    }
                    guard let unicode = Unicode.Scalar(scalar) else { throw fail("Unpaired surrogate") }
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                case 0x00..<0x20:
                    throw fail("Invalid control character")
                default:
                    out.append(byte)
                }
            }
            throw fail("Unterminated string")
        }

        mutating func hex4() throws -> UInt32 {
            guard bytes.count - index >= 4,
                  let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16) else {
                throw fail("Invalid \\uXXXX escape")
            }
            index += 4
            return value
        }

        /// `-?(0|[1-9]\d*)(\.\d+)?([eE][-+]?\d+)?`, Python's number grammar.
        mutating func number() throws -> JSONValue {
            let start = index
            func digits() -> Int {
                let from = index
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
                return index - from
            }
            if bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count else { throw fail("Expecting value") }
            if bytes[index] == UInt8(ascii: "0") { index += 1 } else if digits() == 0 { throw fail("Expecting value") }
            if index < bytes.count, bytes[index] == UInt8(ascii: "."), index + 1 < bytes.count,
               (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index + 1]) {
                index += 1
                _ = digits()
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                let save = index
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                if digits() == 0 { index = save }
            }
            let lexeme = String(decoding: bytes[start..<index], as: UTF8.self)
            guard let value = Double(lexeme) else { throw fail("Invalid number") }
            return .number(lexeme, value)
        }
    }

    // MARK: - Writing

    /// The value as `json.dumps(value, ensure_ascii=False, separators=(",", ":"))` writes it: no whitespace, characters
    /// unescaped except `"`, `\` and control characters.
    var written: String {
        var out = ""
        write(to: &out)
        return out
    }

    private func write(to out: inout String) {
        switch self {
        case .object(let members):
            out += "{"
            for (i, member) in members.enumerated() {
                if i > 0 { out += "," }
                Self.writeString(member.key, to: &out)
                out += ":"
                member.value.write(to: &out)
            }
            out += "}"
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(to: &out)
            }
            out += "]"
        case .string(let string): Self.writeString(string, to: &out)
        case .number(let lexeme, _): out += lexeme
        case .bool(let value): out += value ? "true" : "false"
        case .null: out += "null"
        }
    }

    /// Python's `py_encode_basestring`.
    private static func writeString(_ string: String, to out: inout String) {
        out += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\u{00}"..."\u{1F}": out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}
