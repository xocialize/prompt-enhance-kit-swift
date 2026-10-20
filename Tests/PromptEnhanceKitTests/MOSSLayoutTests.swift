import CryptoKit
import XCTest
import MLXToolKit
@testable import PromptEnhanceKit

/// v0.7 (AB-D-0155, E3): MOSS-Image's layout. The skill's texts verbatim, its compiler ported (`MOSSLayout`), and the
/// canvas a layout is laid out for. The compiler tests are the vendor's own (`scripts/test_compile_prompt.py`), ported.
final class MOSSLayoutTests: XCTestCase {

    /// The vendor test's draft: a 1536×1024 canvas, one text item with CJK, a newline, quotes and an emoji.
    static let draft = ##"""
        {"width": 1536, "height": 1024, "bbox_coord_space": "abs", "bbox_format": "xyxy",
         "summary": {"meta": ["poster"], "canvas": "single", "caption": "A ceramic campaign."},
         "items": [{"label": "text", "caption": "Dark-green lettering.", "text": "把日常，过成诗。\n\"MOSS\" 🪴",
                    "bbox": [928, 272, 1408, 448]}]}
        """##

    func compiled(_ json: String) throws -> MOSSLayout.Compiled { try MOSSLayout.compile(json) }

    func rejects(_ json: String, _ message: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try MOSSLayout.compile(json), file: file, line: line) { error in
            if let message { XCTAssertTrue("\(error)".contains(message), "\(error)", file: file, line: line) }
        }
    }

    /// `draft` with `key` set to `value` (raw JSON) at the top level, or in its item.
    func draft(set key: String, to value: String, inItem: Bool = false) -> String {
        var object = try! JSONValue.parse(Self.draft)
        guard case .object(var root) = object else { fatalError() }
        let parsed = try! JSONValue.parse(value)
        if inItem {
            let i = root.firstIndex { $0.key == "items" }!
            guard case .array(var items) = root[i].value, case .object(var item) = items[0] else { fatalError() }
            if let j = item.firstIndex(where: { $0.key == key }) { item[j].value = parsed } else { item.append((key, parsed)) }
            items[0] = .object(item)
            root[i].value = .array(items)
        } else if let j = root.firstIndex(where: { $0.key == key }) {
            root[j].value = parsed
        } else {
            root.append((key, parsed))
        }
        object = .object(root)
        return object.written
    }

    // MARK: - The vendor's tests

    func testLandscapeConversionPreservesContentAndSource() throws {
        let result = try compiled(Self.draft)
        // `json.dumps(result, ensure_ascii=False, separators=(",", ":"))`, character for character.
        XCTAssertEqual(result.prompt, ##"{"summary":{"meta":["poster"],"canvas":"single","caption":"A ceramic campaign."},"##
                       + ##""items":[{"label":"text","caption":"Dark-green lettering.","text":"把日常，过成诗。\n\"MOSS\" 🪴","##
                       + ##""bbox":[-240,160,-64,640]}],"bbox_coord_space":"abs_centralized","bbox_format":"yxyx"}"##)
        XCTAssertFalse(result.prompt.contains("\n"), "one physical line")
        XCTAssertFalse(result.prompt.contains("width"))
        XCTAssertEqual(result.canvas, CanvasSize(width: 1536, height: 1024))
        let back = try JSONValue.parse(result.prompt)
        XCTAssertEqual(back["items"], .array([.object([("label", .string("text")), ("caption", .string("Dark-green lettering.")),
                                                       ("text", .string("把日常，过成诗。\n\"MOSS\" 🪴")),
                                                       ("bbox", .array([-240, 160, -64, 640].map { .number("\($0)", Double($0)) }))])]))
    }

    func testPortraitEdgesAndFractionalEnclosure() throws {
        func box(_ values: [Double]) throws -> [Int] {
            try MOSSLayout.centeredBox(.array(values.map { .number("\($0)", $0) }), width: 768, height: 1344, "box")
        }
        XCTAssertEqual(try box([0, 0, 768, 1344]), [-672, -384, 672, 384])
        XCTAssertEqual(try box([10.9, 20.1, 100.01, 200.99]), [-652, -374, -471, -283])
        XCTAssertEqual(try box([1.00000000001, 2, 100, 200]), [-670, -383, -472, -284])
    }

    func testInvalidGeometryIsRejected() {
        let cases = ["[-1, 0, 100, 100]", "[0, 0, 1537, 100]", "[0, 0, 100, 1025]", "[100, 0, 50, 100]", "[0, 0, 0, 100]",
                     "[0, 0, 100]", "[true, 0, 100, 100]", "[0, 0, 1e400, 100]", #"[0, 0, "100", 100]"#,
                     "[0, 0, 0.00000000001, 100]"]
        for box in cases {
            XCTAssertThrowsError(try MOSSLayout.centeredBox(try JSONValue.parse(box), width: 1536, height: 1024, "box"), box)
            rejects(draft(set: "bbox", to: box, inItem: true))
        }
        rejects(#"{"width": 1536, "height": 1024, "bbox_coord_space": "abs", "bbox_format": "xyxy", "summary": {"caption": "x"}, "items": [{"label": "object", "caption": "y", "bbox": [0, 0, NaN, 100]}]}"#)
    }

    func testInvalidDimensionsAndConventionsAreRejected() {
        for (field, value) in [("width", "1023"), ("height", "0"), ("width", "true"), ("height", "1024.0"), ("width", "1.024e3"),
                               ("bbox_coord_space", #""abs_centralized""#), ("bbox_coord_space", #""normalized_1000""#),
                               ("bbox_format", #""yxyx""#)] {
            rejects(draft(set: field, to: value))
        }
        rejects(draft(set: "width", to: "1023"), "width must be a positive integer multiple of 16")
        rejects(draft(set: "bbox_format", to: #""yxyx""#), "Draft bbox_format must be xyxy")
    }

    func testUnrepresentableContentIsNotSilentlyDropped() {
        for (field, value) in [("children", #"[{"bbox": [0, 0, 20, 20]}]"#), ("font_size", "32"), ("parent", #""cup""#)] {
            rejects(draft(set: field, to: value, inItem: true), "items[0]: unknown fields ['\(field)']")
        }
        rejects(Self.draft.replacingOccurrences(of: ##""text": "把日常，过成诗。\n\"MOSS\" 🪴","##, with: ""), "literal text")
        rejects(draft(set: "canvas", to: #""1536x1024""#), "Layout draft: unknown fields ['canvas']")
    }

    func testCaptionIsPlainTextAndKeepsExactWording() throws {
        let caption = "An ivory cup marked \"茶\".\nPreserve this second line."
        XCTAssertEqual(try compiled(#"{"caption": "An ivory cup marked \"茶\".\nPreserve this second line."}"#),
                       MOSSLayout.Compiled(prompt: caption, canvas: nil))
        rejects(#"{"caption": ""}"#)
        rejects(#"{"caption": "x", "items": []}"#)
    }

    func testDuplicateKeysAndNonFiniteConstantsAreRejected() {
        rejects(#"{"caption":"one","caption":"two"}"#, "Duplicate JSON key: caption")
        rejects(#"{"caption":NaN}"#)
        rejects(#"{"caption":Infinity}"#)
    }

    // MARK: - The port's own

    func testTheSkillsExampleCompilesAsItsReferenceSays() throws {
        // references/layout.md's example: "For the cup, conversion yields [-288,-592,352,32]".
        let example = try XCTUnwrap(VendorPrompts.mossImageLayoutReference.firstMatch(of: /```json\n(?<json>[\s\S]*?)\n```/))
        let result = try compiled(String(example.json))
        XCTAssertTrue(result.prompt.contains(#""bbox":[-288,-592,352,32]"#), result.prompt)
        XCTAssertTrue(result.prompt.hasPrefix(#"{"summary":{"meta":["product campaign","studio photography"],"canvas":"single","#))
        XCTAssertTrue(result.prompt.contains(#""text":"一杯温暖\n一刻从容""#), "a newline stays escaped in the JSON")
        XCTAssertEqual(result.canvas, CanvasSize(width: 1536, height: 1024))
    }

    func testAnAnswerWithProseAroundItIsReadFromBraceToBrace() throws {
        let result = try compiled("Here is the draft:\n```json\n" + Self.draft + "\n```")
        XCTAssertEqual(result.canvas, CanvasSize(width: 1536, height: 1024))
        rejects("No JSON here.", "isn't JSON")
    }

    func testControlCharactersAreEscapedAsPythonDoes() {
        XCTAssertEqual(JSONValue.string("a\u{01}b\tc\u{1F}\u{7F}é/").written, #""a\u0001b\tc\u001f"# + "\u{7F}é/\"")
    }

    // MARK: - The profile

    func testTheSkillTextsAreVerbatim() {
        func sha256(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
        XCTAssertEqual(sha256(VendorPrompts.mossImageSkill), "f559b9c40cca4c944f1b6dae8306928a92211afa5543ad1e83a0616fc63405d4")
        XCTAssertEqual(sha256(VendorPrompts.mossImageLayoutReference),
                       "2bcde35aa763acd76941d87571edfd2b1cfd191dd5053b28b76f435f194c2cbc")
        XCTAssertTrue(VendorPrompts.mossImageSkill.hasPrefix("---\nname: moss-image-prompt-enhancer\n"))
        XCTAssertTrue(VendorPrompts.mossImageLayoutReference.hasSuffix("Recompile after every geometry or canvas edit."))
    }

    func testTheProfileIsAnOptionalLargeLayoutProfile() {
        let moss = ImageModelProfiles.moss
        XCTAssertEqual(moss.models, ["moss-image-sft", "moss-image-base"])
        XCTAssertEqual(moss.policy, .optional)
        XCTAssertEqual(moss.backbone, .large)
        XCTAssertEqual(moss.compiler, .mossImageLayout)
        XCTAssertTrue(moss.laysOutCanvas)
        XCTAssertFalse(ImageModelProfiles.senseNova.laysOutCanvas)
        XCTAssertEqual(moss.source.license, "Apache-2.0")
        XCTAssertTrue(moss.source.verbatim)
        XCTAssertEqual(PromptEnhancer.decision("a fox", profile: moss, task: .textToImage), .notRecommended)
        XCTAssertNil(PromptEnhancer.decision("a fox", profile: moss, task: .textToImage, mode: .always))
        XCTAssertEqual(PromptEnhancer.decision(#"{"summary": {"caption": "x"}, "items": []}"#, profile: moss,
                                               task: .textToImage, mode: .always), .passedThrough, "a layout already")
    }

    func testTheRequestCarriesTheSkillTheReferenceAndTheTarget() throws {
        let enhancer = PromptEnhancer(parameters: LLMParameters(temperature: 0.7, maxTokens: 512, seed: 4))
        let made = try XCTUnwrap(enhancer.makeRequest(" a poster ", profile: ImageModelProfiles.moss, task: .textToImage,
                                                      targetSize: (1024, 1536)))
        XCTAssertEqual(made.request.responseFormat, .json(container: .object))
        let system = try XCTUnwrap(made.request.messages.first { $0.role == .system }?.content)
        XCTAssertTrue(system.hasPrefix(VendorPrompts.mossImageSkill))
        XCTAssertTrue(system.hasSuffix(VendorPrompts.mossImageLayoutReference))
        let user = try XCTUnwrap(made.request.messages.last?.content)
        XCTAssertTrue(user.hasSuffix("give no other item a `text` field.\n\nImage idea: a poster\n\nTarget resolution: 1024x1536."), user)
        XCTAssertEqual(made.request.parameters.maxTokens, 4096)
        XCTAssertEqual(made.request.parameters.seed, 4)
    }

    // MARK: - Enhancing

    func testALayoutAnswerIsCompiledAndReportsItsCanvas() async throws {
        let result = try await PromptEnhancer().enhance("a ceramic campaign", profile: ImageModelProfiles.moss,
                                                        task: .textToImage, mode: .always,
                                                        targetSize: (1536, 1024)) { _ in Self.draft }
        XCTAssertEqual(result.outcome, .enhanced)
        XCTAssertEqual(result.prompt, try compiled(Self.draft).prompt)
        XCTAssertEqual(result.canvas, CanvasSize(width: 1536, height: 1024))
        XCTAssertNil(result.suggestedSize)
        XCTAssertEqual(result.attempts, 1)
    }

    func testALayoutForAnotherCanvasFails() async throws {
        let result = try await PromptEnhancer().enhance("a ceramic campaign", profile: ImageModelProfiles.moss,
                                                        task: .textToImage, mode: .always,
                                                        targetSize: (1024, 1024)) { _ in Self.draft }
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.prompt, "a ceramic campaign")
        XCTAssertNil(result.canvas)
        XCTAssertTrue(result.failure?.hasPrefix("The layout is for a 1536x1024 canvas, not the target 1024x1024.") == true)
    }

    func testADraftTheScriptRejectsFailsWithItsMessage() async throws {
        let outside = draft(set: "bbox", to: "[0, 0, 1600, 100]", inItem: true)
        let result = try await PromptEnhancer().enhance("a ceramic campaign", profile: ImageModelProfiles.moss,
                                                        task: .textToImage, mode: .always, targetSize: (1536, 1024)) { _ in
            outside
        }
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.failure, "items[0].bbox exceeds the 1536x1024 canvas; after a retry: items[0].bbox exceeds the "
                       + "1536x1024 canvas")
    }

    func testARejectedDraftGoesBackOnceWithTheScriptsMessage() async throws {
        let bad = draft(set: "label", to: #""panel""#, inItem: true)
        let requests = Requests()
        let result = try await PromptEnhancer().enhance("a ceramic campaign", profile: ImageModelProfiles.moss,
                                                        task: .textToImage, mode: .always, targetSize: (1536, 1024)) { request in
            requests.append(request)
            return requests.count == 1 ? bad : Self.draft
        }
        XCTAssertEqual(result.outcome, .enhanced)
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.failure, "items[0].label must be object, character or text", "why the first draft was rejected")
        XCTAssertEqual(result.canvas, CanvasSize(width: 1536, height: 1024))
        let (first, second) = (requests.all[0], requests.all[1])
        XCTAssertEqual(second.messages.first?.content, first.messages.first?.content, "the same system turn")
        XCTAssertEqual(second.messages.count, 2)
        XCTAssertEqual(second.messages.last?.content, (first.messages.last?.content ?? "") + "\n\nYour draft was:\n\n" + bad
                       + "\n\ncompile_prompt.py rejected it: items[0].label must be object, character or text\n\nFix the draft "
                       + "and answer with the whole corrected draft, and nothing else. Leave a field out rather than empty (an "
                       + "item with no visible wording has no `text`), use only the fields references/layout.md lists, and "
                       + "give every box x_min < x_max and y_min < y_max inside the canvas.")
        XCTAssertEqual(second.parameters.seed, first.parameters.seed)
        XCTAssertEqual(second.responseFormat, first.responseFormat)
    }

    func testADraftRejectedTwiceFailsWithBothMessages() async throws {
        let result = try await PromptEnhancer().enhance("a ceramic campaign", profile: ImageModelProfiles.moss,
                                                        task: .textToImage, mode: .always, targetSize: (1024, 1024)) { _ in
            Self.draft
        }
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.failure, "The layout is for a 1536x1024 canvas, not the target 1024x1024.; after a retry: "
                       + "The layout is for a 1536x1024 canvas, not the target 1024x1024.")
    }

    func testAProfileWithoutACompilerIsNotRetried() async throws {
        let requests = Requests()
        let result = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.senseNova, task: .textToImage) { request in
            requests.append(request)
            return "no JSON"
        }
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.attempts, 1)
        XCTAssertEqual(requests.count, 1)
        let skipped = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.moss, task: .textToImage) { _ in "" }
        XCTAssertEqual(skipped.outcome, .notRecommended)
        XCTAssertEqual(skipped.attempts, 0)
    }

    func testACaptionAnswerIsItsCaptionWithNoCanvas() async throws {
        let result = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.moss, task: .textToImage,
                                                        mode: .always, targetSize: (1024, 1024)) { _ in
            #"{"caption": "A red fox in fresh snow."}"#
        }
        XCTAssertEqual(result.outcome, .enhanced)
        XCTAssertEqual(result.prompt, "A red fox in fresh snow.")
        XCTAssertNil(result.canvas)
    }
}

/// The requests a fake backbone received.
final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [LLMRequest] = []

    func append(_ request: LLMRequest) { lock.withLock { requests.append(request) } }
    var all: [LLMRequest] { lock.withLock { requests } }
    var count: Int { all.count }
}
