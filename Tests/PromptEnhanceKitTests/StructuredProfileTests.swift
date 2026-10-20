import CryptoKit
import XCTest
import MLXToolKit
@testable import PromptEnhanceKit

/// v0.6 (AB-D-0155, E3): the structured profiles, SenseNova U1.5's Render JSON and Ming-Image's layers, on a `large`
/// backbone; JSON written out in the backbone's key order; the size an answer suggests.
final class StructuredProfileTests: XCTestCase {

    // MARK: - The vendor texts

    func testStructuredVendorTextsAreVerbatim() {
        func sha256(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
        // The SHA-256s of the pinned sources' text (VendorPrompts' doc comments name the commits).
        XCTAssertEqual(sha256(VendorPrompts.senseNovaImagePE), "f2229c6a22d04de0e6aa92cd5eb76484188a7295c1801df095b5990dc2748c44")
        XCTAssertEqual(sha256(VendorPrompts.mingImageRewriter), "dd47af60155dfb8187b1fb4e915362b6d6e3d7b01c213167fbaf12c322613fbf")
        XCTAssertTrue(VendorPrompts.senseNovaImagePE.contains("- 16:9 | landscape | 2720 x 1536"))
        XCTAssertTrue(VendorPrompts.mingImageRewriter.hasSuffix("bbox validity, and completeness."))
    }

    func testStructuredProfilesAreLargeJSONProfiles() {
        let sense = ImageModelProfiles.senseNova, ming = ImageModelProfiles.mingImage
        XCTAssertEqual(sense.output, .json(layout: .compact))
        XCTAssertEqual(ming.output, .json(layout: .pretty))
        XCTAssertEqual([sense.backbone, ming.backbone], [.large, .large])
        XCTAssertEqual(sense.policy, .recommended)
        XCTAssertEqual(ming.policy, .optional)
        XCTAssertEqual(sense.sampling.maxTokens, 4096, "the vendor's max_output_tokens")
        XCTAssertEqual(sense.source.license, "Apache-2.0")
        XCTAssertEqual(ming.source.license, "MIT")
    }

    // MARK: - Decisions

    func testSenseNovaRewritesEveryProseBriefUnderAuto() {
        let long = Array(repeating: "detail", count: 120).joined(separator: " ")
        for brief in ["a fox", long, "一只红狐狸站在新雪里"] {
            XCTAssertNil(PromptEnhancer.decision(brief, profile: ImageModelProfiles.senseNova, task: .textToImage), brief)
        }
        XCTAssertEqual(PromptEnhancer.decision(#"{"subjects": []}"#, profile: ImageModelProfiles.senseNova, task: .textToImage),
                       .passedThrough, "Render JSON already")
        XCTAssertEqual(PromptEnhancer.decision("a fox", profile: ImageModelProfiles.mingImage, task: .textToImage),
                       .notRecommended)
        XCTAssertNil(PromptEnhancer.decision("a fox", profile: ImageModelProfiles.mingImage, task: .textToImage, mode: .always))
    }

    // MARK: - The request

    func testTheRequestIsConstrainedJSONWithTheVendorTextAndTheTargetSize() throws {
        let enhancer = PromptEnhancer(parameters: LLMParameters(temperature: 0.7, maxTokens: 512, seed: 3))
        let made = try XCTUnwrap(enhancer.makeRequest("  a book-fair poster ", profile: ImageModelProfiles.senseNova,
                                                      task: .textToImage, targetSize: (1664, 2496)))
        XCTAssertEqual(made.request.responseFormat, .json(container: .object))
        XCTAssertEqual(made.request.messages.map(\.role), [ChatMessage.Role.system, .user])
        XCTAssertEqual(made.request.messages.first?.content, VendorPrompts.senseNovaImagePE)
        XCTAssertEqual(made.request.messages.last?.content, "a book-fair poster\n\nTarget resolution: 1664x2496.")
        XCTAssertEqual(made.request.parameters.maxTokens, 4096)
        XCTAssertEqual(made.request.parameters.seed, 3)
    }

    // MARK: - Reading the answer

    func testCompactJSONKeepsTheBackbonesKeyOrderAndSuggestsItsCanvas() async throws {
        let answer = """
            Here is the render brief:
            {"subjects": [{"description": "a fox", "count_anatomy": "one"}], "scene": {"setting": "snow"},
             "visible_copy": [], "canvas": {"aspect_ratio": "3:2", "orientation": "landscape", "resolution": "2496 x 1664"},
             "negative": "blur, extra limbs"}
            """
        let result = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.senseNova, task: .textToImage) { _ in
            answer
        }
        XCTAssertEqual(result.outcome, .enhanced)
        XCTAssertEqual(result.prompt, #"{"subjects":[{"description":"a fox","count_anatomy":"one"}],"scene":{"setting":"snow"},"#
                       + #""visible_copy":[],"canvas":{"aspect_ratio":"3:2","orientation":"landscape","resolution":"2496 x 1664"},"#
                       + #""negative":"blur, extra limbs"}"#, "the model's order, not sorted; read from { to }")
        XCTAssertEqual(result.suggestedSize, SuggestedSize(width: 2496, height: 1664, aspectRatio: "3:2"))
        XCTAssertEqual(result.fields, ["negative": "blur, extra limbs"])
    }

    func testPrettyJSONMatchesPythonsIndentTwo() async throws {
        let answer = ##"{"canvas_settings":{"aspect_ratio":"2:3, 1664 × 2496 px","ambient_lighting":"soft","image_style":"flat"},"##
            + ##""layers":[{"description":"Title \"NIGHT SHIFT\"","coordinates":"cx: 0.500, cy: 0.200, w: 0.800, h: 0.100","##
            + ##""hierarchy_and_relation":"top","color_specs":["#FFFFFF","#101820"]},{"description":"empty","##
            + ##""coordinates":"cx: 0.500, cy: 0.500, w: 1.000, h: 1.000","hierarchy_and_relation":"","color_specs":[ ]}]}"##
        let result = try await PromptEnhancer().enhance("a poster", profile: ImageModelProfiles.mingImage, task: .textToImage,
                                                        mode: .always) { _ in answer }
        // `json.dumps(value, ensure_ascii=False, indent=2)` of the same value.
        XCTAssertEqual(result.prompt, """
            {
              "canvas_settings": {
                "aspect_ratio": "2:3, 1664 × 2496 px",
                "ambient_lighting": "soft",
                "image_style": "flat"
              },
              "layers": [
                {
                  "description": "Title \\"NIGHT SHIFT\\"",
                  "coordinates": "cx: 0.500, cy: 0.200, w: 0.800, h: 0.100",
                  "hierarchy_and_relation": "top",
                  "color_specs": [
                    "#FFFFFF",
                    "#101820"
                  ]
                },
                {
                  "description": "empty",
                  "coordinates": "cx: 0.500, cy: 0.500, w: 1.000, h: 1.000",
                  "hierarchy_and_relation": "",
                  "color_specs": []
                }
              ]
            }
            """)
        XCTAssertEqual(result.suggestedSize, SuggestedSize(width: 1664, height: 2496, aspectRatio: "2:3"))
    }

    func testAnAnswerThatIsNoJSONFails() async throws {
        let result = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.senseNova, task: .textToImage) { _ in
            "A fox in the snow, rendered softly."
        }
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.prompt, "a fox")
        XCTAssertNil(result.suggestedSize)
    }

    func testSizesReadFromCanvasStrings() {
        XCTAssertEqual(JSONText.size(in: "2720 x 1536"), SuggestedSize(width: 2720, height: 1536))
        XCTAssertEqual(JSONText.size(in: "1:1, 2048 × 2048 px"), SuggestedSize(width: 2048, height: 2048, aspectRatio: "1:1"))
        XCTAssertEqual(JSONText.size(in: "9:16, 720 × 1280 px"), SuggestedSize(width: 720, height: 1280, aspectRatio: "9:16"))
        XCTAssertEqual(JSONText.size(in: "16:9"), SuggestedSize(aspectRatio: "16:9"))
        XCTAssertNil(JSONText.size(in: "landscape"))
        XCTAssertEqual(SuggestedSize(aspectRatio: "3:2").ratio, 1.5)
        XCTAssertEqual(SuggestedSize(width: 1536, height: 2720).ratio ?? 0, 1536.0 / 2720, accuracy: 1e-9)
    }

    func testTheFirstSizeFieldWinsAndTheRestFillIn() async throws {
        var profile = ImageModelProfiles.senseNova
        profile.sizeFields = [["canvas", "aspect_ratio"], ["canvas", "resolution"]]
        let result = try await PromptEnhancer().enhance("a fox", profile: profile, task: .textToImage) { _ in
            #"{"canvas": {"aspect_ratio": "16:9", "orientation": "landscape", "resolution": "2720 x 1536"}}"#
        }
        XCTAssertEqual(result.suggestedSize, SuggestedSize(width: 2720, height: 1536, aspectRatio: "16:9"))
    }
}
