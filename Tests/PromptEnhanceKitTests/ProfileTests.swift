import XCTest
import MLXToolKit
@testable import PromptEnhanceKit

/// v0.5: model profiles, outcomes for provenance, cancellation that propagates, a timeout, JSON output.
final class ProfileTests: XCTestCase {

    // MARK: - Library

    func testImageModelsCoverEachCatalogModel() {
        let library = ProfileLibrary.imageModels()
        XCTAssertEqual(library.profiles.map(\.id), ["flux2-klein", "mage-flow", "qwen-image", "z-image"])
        for (model, profile) in [("z-image-turbo", "z-image"), ("z-image", "z-image"), ("qwen-image-flash", "qwen-image"),
                                 ("klein-4b", "flux2-klein"), ("klein-4b-base", "flux2-klein"),
                                 ("mage-flow", "mage-flow"), ("mage-flow-turbo", "mage-flow")] {
            XCTAssertEqual(library.profile(forModel: model)?.id, profile, model)
        }
        XCTAssertNil(library.profile(forModel: "flux-3-klein"), "FLUX 3 Klein keeps its own upsampler")
    }

    func testRegisterReplacesAProfileAndRebindsItsModels() {
        var library = ProfileLibrary.imageModels()
        var tuned = ImageModelProfiles.mageFlow
        tuned.version = 2
        tuned.models = ["mage-flow"]
        library.register(tuned)
        XCTAssertEqual(library.profile(forModel: "mage-flow")?.version, 2)
        XCTAssertNil(library.profile(forModel: "mage-flow-turbo"), "the replaced profile's models are released")
    }

    func testMergeOverlaysAPack() {
        var base = ProfileLibrary.imageModels()
        var tuned = ImageModelProfiles.qwenImage
        tuned.version = 9
        base.merge(ProfileLibrary([tuned]))
        XCTAssertEqual(base.profile(forModel: "qwen-image-flash")?.version, 9)
        XCTAssertEqual(base.profiles.count, 4)
    }

    func testTemplateLibraryMerge() {
        var lib = TemplateLibrary()
        lib.merge(TemplateLibrary.ltxVideo())
        XCTAssertEqual(lib.template(for: .textToVideo, task: .textToVideo), LTXVideoProfile.textToVideo)
        XCTAssertNotNil(lib.template(for: .textToImage, task: .textToImage))
    }

    // MARK: - Decisions

    func testAutoFollowsThePolicy() {
        let short = "a red fox in snow"
        XCTAssertEqual(PromptEnhancer.decision(short, profile: ImageModelProfiles.zImage, task: .textToImage, mode: .auto),
                       .notRecommended)
        XCTAssertNil(PromptEnhancer.decision(short, profile: ImageModelProfiles.qwenImage, task: .textToImage, mode: .auto))
        XCTAssertNil(PromptEnhancer.decision(short, profile: ImageModelProfiles.zImage, task: .textToImage, mode: .always))
        var required = ImageModelProfiles.flux2Klein
        required.policy = .required
        let long = Array(repeating: "word", count: 200).joined(separator: " ")
        XCTAssertNil(PromptEnhancer.decision(long, profile: required, task: .textToImage, mode: .auto))
    }

    func testADetailedBriefPassesThroughInAutoButNotAlways() {
        let long = Array(repeating: "detail", count: 61).joined(separator: " ")
        XCTAssertEqual(PromptEnhancer.decision(long, profile: ImageModelProfiles.flux2Klein, task: .textToImage, mode: .auto),
                       .passedThrough)
        XCTAssertNil(PromptEnhancer.decision(long, profile: ImageModelProfiles.flux2Klein, task: .textToImage, mode: .always))
    }

    func testAStructuredBriefAlwaysPassesThrough() {
        let layout = #"{"summary": {"caption": "a poster"}, "items": []}"#
        XCTAssertEqual(PromptEnhancer.decision(layout, profile: ImageModelProfiles.qwenImage, task: .textToImage,
                                               mode: .always), .passedThrough)
        XCTAssertNil(PromptEnhancer.decision("{not json", profile: ImageModelProfiles.qwenImage, task: .textToImage,
                                             mode: .always))
    }

    func testMissingInstructionAndVisionTasks() {
        XCTAssertEqual(PromptEnhancer.decision("x", profile: ImageModelProfiles.qwenImage, task: .imageEdit, mode: .always),
                       .noInstruction)
        var editing = ImageModelProfiles.flux2Klein
        editing.instructions[.imageEdit] = EnhanceInstructionSet(EnhanceInstruction(system: "edit"))
        XCTAssertEqual(PromptEnhancer.decision("x", profile: editing, task: .imageEdit, mode: .always), .needsVision)
    }

    func testWordCountCountsIdeographsInPairs() {
        XCTAssertEqual(PromptEnhancer.wordCount("a red fox"), 3)
        XCTAssertEqual(PromptEnhancer.wordCount("一只可爱的小猫"), 4)              // 7 ideographs
        XCTAssertEqual(PromptEnhancer.wordCount("a poster 写着 欢迎"), 4)
    }

    // MARK: - Requests

    func testQwenPicksItsInstructionByScript() throws {
        let enhancer = PromptEnhancer(parameters: LLMParameters(temperature: 0.7, maxTokens: 512, seed: 7))
        let en = try XCTUnwrap(enhancer.makeRequest("a cat in a garden", profile: ImageModelProfiles.qwenImage,
                                                    task: .textToImage))
        XCTAssertFalse(en.chinese)
        XCTAssertEqual(en.request.messages.first?.content, "You are a helpful assistant.")
        XCTAssertTrue(en.request.messages.last!.content.hasSuffix("User Input: a cat in a garden\n\n Rewritten Prompt:"))
        XCTAssertEqual(en.request.parameters.seed, 7, "the caller's seed survives the profile's overrides")
        XCTAssertEqual(en.request.mode, .promptEnhance)
        XCTAssertNil(en.request.responseFormat)

        let zh = try XCTUnwrap(enhancer.makeRequest("一只可爱的小猫坐在花园里", profile: ImageModelProfiles.qwenImage,
                                                    task: .textToImage))
        XCTAssertTrue(zh.chinese)
        XCTAssertTrue(zh.request.messages.last!.content.hasSuffix("用户输入：一只可爱的小猫坐在花园里\n改写输出："))
    }

    func testZImagePutsTheBriefInTheInstructionAsTheVendorDoes() throws {
        let made = try XCTUnwrap(PromptEnhancer().makeRequest("a lighthouse", profile: ImageModelProfiles.zImage,
                                                              task: .textToImage))
        XCTAssertEqual(made.request.messages.count, 2)
        XCTAssertTrue(made.request.messages[0].content.hasSuffix("用户输入 prompt: a lighthouse"))
        XCTAssertFalse(made.request.messages[0].content.contains("{prompt}"))
        XCTAssertEqual(made.request.messages[0].content,
                       VendorPrompts.zImage.replacingOccurrences(of: "{prompt}", with: "a lighthouse"),
                       "the vendor's text is sent unchanged")
        XCTAssertEqual(made.request.messages[1].content, ImageModelProfiles.zImageNudge)
        XCTAssertEqual(made.request.parameters.temperature, 0.7)
        XCTAssertEqual(made.request.parameters.topP, 0.8)
        XCTAssertEqual(made.request.parameters.maxTokens, 768)
    }

    func testZImageV2RecordsItsUserTurnNudge() throws {
        let profile = ImageModelProfiles.zImage
        XCTAssertEqual(profile.version, 2)
        XCTAssertTrue(profile.source.verbatim, "the vendor's text itself is unchanged")
        let adaptation = try XCTUnwrap(profile.source.adaptation)
        XCTAssertTrue(adaptation.contains("user turn"), adaptation)
        let nudge = ImageModelProfiles.zImageNudge
        XCTAssertTrue(nudge.contains("language of the user's prompt"), "a Chinese brief keeps a Chinese answer")
        XCTAssertTrue(nudge.contains("rather than a comma-separated list of tags"), "prose over tags")
        XCTAssertFalse(nudge.contains("{prompt}"), "the brief stays in the vendor's slot only")
        XCTAssertFalse(nudge.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) })
        XCTAssertFalse(ImageModelProfiles.zImageNudgeChinese.contains("{prompt}"))
    }

    func testAChineseBriefGetsTheChineseNudgeAndTheSameVendorText() throws {
        // An English nudge pulled the answer to "一只红狐狸站在新雪里" into English (the 0.5.1 live gate).
        let brief = "一只红狐狸站在新雪里"
        let made = try XCTUnwrap(PromptEnhancer().makeRequest(brief, profile: ImageModelProfiles.zImage,
                                                              task: .textToImage))
        XCTAssertTrue(made.chinese)
        XCTAssertEqual(made.request.messages[0].content,
                       VendorPrompts.zImage.replacingOccurrences(of: "{prompt}", with: brief))
        XCTAssertEqual(made.request.messages[1].content, ImageModelProfiles.zImageNudgeChinese)
        XCTAssertTrue(PromptEnhancer.containsCJK(ImageModelProfiles.zImageNudgeChinese))
        XCTAssertEqual(made.request.parameters.temperature, 0.7, "the vendor's sampling either way")
    }

    func testKleinV2NoLongerListsWhatToLeaveOut() throws {
        let profile = ImageModelProfiles.flux2Klein
        XCTAssertEqual(profile.version, 2)
        let system = try XCTUnwrap(profile.instructions[.textToImage]?.standard.system)
        // v1's "Don't add text, logos or people…" came back as "No text, logos, or other people are present."
        XCTAssertFalse(system.contains("logos"))
        XCTAssertFalse(system.contains("people"))
        XCTAssertTrue(system.contains("Every sentence must describe something visible in the image"))
        XCTAssertTrue(system.contains("never say what is absent"))
        // "Put words in the image only when…" primed invented signs and absence sentences: the text rule is conditional.
        XCTAssertTrue(system.contains("When the brief asks for words in the image"))
        XCTAssertFalse(system.contains("only when"))
        // What v1 asked for is kept: quoted words verbatim, prose, no quality tags.
        XCTAssertTrue(system.contains("inside double quotes"))
        XCTAssertTrue(system.contains("never translate them"))
        XCTAssertTrue(system.contains("\"8K\""))
        XCTAssertEqual(profile.source, .original)
    }

    func testANilSystemSendsNoSystemTurn() throws {
        var dedicated = ImageModelProfiles.mageFlow
        dedicated.instructions[.textToImage] = EnhanceInstructionSet(EnhanceInstruction(system: nil))
        let made = try XCTUnwrap(PromptEnhancer().makeRequest("x", profile: dedicated, task: .textToImage,
                                                              targetSize: (1024, 768)))
        XCTAssertEqual(made.request.messages.map(\.role), [.user])
        XCTAssertEqual(made.request.messages[0].content, "x\n\nTarget resolution: 1024x768.")
    }

    // MARK: - Enhancing

    func testEnhancedAnswersGetTheSuffixAndOneLine() async throws {
        let result = try await PromptEnhancer().enhance("a cat", profile: ImageModelProfiles.qwenImage,
                                                        task: .textToImage) { _ in "A tabby cat\non a sunlit bench." }
        XCTAssertEqual(result.outcome, .enhanced)
        XCTAssertEqual(result.prompt, "A tabby cat on a sunlit bench. Ultra HD, 4K, cinematic composition")
        XCTAssertEqual(result.original, "a cat")
        XCTAssertEqual(result.profileID, "qwen-image")
        XCTAssertEqual(result.profileVersion, 1)

        let zh = try await PromptEnhancer().enhance("一只猫", profile: ImageModelProfiles.qwenImage,
                                                    task: .textToImage) { _ in "一只虎斑猫坐在长椅上。" }
        XCTAssertTrue(zh.usedChineseInstruction)
        XCTAssertEqual(zh.prompt, "一只虎斑猫坐在长椅上。超清，4K，电影级构图")
    }

    func testFencesAndWrappingQuotesAreStripped() async throws {
        let fenced = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                        task: .textToImage) { _ in "```\nA red fox in deep snow.\n```" }
        XCTAssertEqual(fenced.prompt, "A red fox in deep snow.")
        let quoted = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                        task: .textToImage) { _ in "“A red fox in deep snow.”" }
        XCTAssertEqual(quoted.prompt, "A red fox in deep snow.")
        let inner = try await PromptEnhancer().enhance("a sign", profile: ImageModelProfiles.flux2Klein,
                                                       task: .textToImage) { _ in #""OPEN" on a sign, "CLOSED" below"# }
        XCTAssertEqual(inner.prompt, #""OPEN" on a sign, "CLOSED" below"#, "quotes inside the prompt are kept")
    }

    func testReasoningIsStrippedAndAnUnfinishedThoughtIsNoAnswer() async throws {
        let closed = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                        task: .textToImage) { _ in
            "<think>\nThe brief is short; add light and setting.\n</think>\n\nA red fox in deep snow at dawn."
        }
        XCTAssertEqual(closed.prompt, "A red fox in deep snow at dawn.")
        let prefilled = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                           task: .textToImage) { _ in "planning…</think>A red fox." }
        XCTAssertEqual(prefilled.prompt, "A red fox.")
        let unfinished = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                            task: .textToImage) { _ in "<think>\nStill thinking about the" }
        XCTAssertEqual(unfinished.outcome, .empty)
        XCTAssertEqual(unfinished.prompt, "a fox")
    }

    func testFailuresFallBackToTheBriefWithAReason() async throws {
        struct Boom: Error {}
        let failed = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                        task: .textToImage) { _ in throw Boom() }
        XCTAssertEqual(failed.outcome, .failed)
        XCTAssertEqual(failed.prompt, "a fox")
        XCTAssertNotNil(failed.failure)

        let empty = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                       task: .textToImage) { _ in "   " }
        XCTAssertEqual(empty.outcome, .empty)
        XCTAssertEqual(empty.prompt, "a fox")
    }

    func testSkippedPromptsNeverCallTheBackbone() async throws {
        let result = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.zImage, task: .textToImage) { _ in
            XCTFail("an optional profile in auto mode must not call the backbone")
            return ""
        }
        XCTAssertEqual(result.outcome, .notRecommended)
        XCTAssertEqual(result.prompt, "a fox")
        XCTAssertFalse(result.applied)
    }

    func testATimeoutReturnsTheBriefPromptly() async throws {
        let start = ContinuousClock.now
        let result = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                        task: .textToImage, timeout: .milliseconds(50)) { _ in
            try await Task.sleep(for: .seconds(5))
            return "too late"
        }
        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertEqual(result.prompt, "a fox")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(2))
    }

    func testCancellationPropagatesInsteadOfReturningTheBrief() async throws {
        let task = Task {
            try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein, task: .textToImage) { _ in
                try await Task.sleep(for: .seconds(5))
                return "too late"
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled enhancement must throw, not hand back the raw prompt")
        } catch is CancellationError {
        }
    }

    func testGeneratorTransportPassesTheTurns() async throws {
        let result = try await PromptEnhancer().enhance("a fox", profile: ImageModelProfiles.flux2Klein,
                                                        task: .textToImage) { system, user in
            XCTAssertTrue(system?.hasPrefix("You write prompts for FLUX.2 [klein]") == true)
            XCTAssertEqual(user, "a fox")
            return "A red fox."
        }
        XCTAssertEqual(result.prompt, "A red fox.")
    }

    // MARK: - JSON output

    func testJSONOutputReadsAFieldAndKeepsTheRest() async throws {
        var profile = ImageModelProfiles.flux2Klein
        profile.output = .json(promptField: "rewritten_prompt")
        let made = try XCTUnwrap(PromptEnhancer().makeRequest("a fox", profile: profile, task: .textToImage))
        XCTAssertEqual(made.request.responseFormat, .json(container: .object))
        let result = try await PromptEnhancer().enhance("a fox", profile: profile, task: .textToImage) { _ in
            #"{"rewritten_prompt": "A red fox in snow.", "wh_ratio": "16:9", "steps": 4}"#
        }
        XCTAssertEqual(result.prompt, "A red fox in snow.")
        XCTAssertEqual(result.fields, ["wh_ratio": "16:9", "steps": "4"])
    }

    func testJSONOutputWithoutAFieldIsTheWholeValueCompacted() async throws {
        var profile = ImageModelProfiles.flux2Klein
        profile.output = .json(schema: #"{"type": "object"}"#)
        let made = try XCTUnwrap(PromptEnhancer().makeRequest("a fox", profile: profile, task: .textToImage))
        XCTAssertEqual(made.request.responseFormat, .jsonSchema(#"{"type": "object"}"#))
        let result = try await PromptEnhancer().enhance("a fox", profile: profile, task: .textToImage) { _ in
            "```json\n{ \"canvas\": {\"w\": 1024}, \"subjects\": [\"fox\"] }\n```"
        }
        XCTAssertEqual(result.prompt, #"{"canvas":{"w":1024},"subjects":["fox"]}"#)
    }

    func testUnreadableJSONFallsBack() async throws {
        var profile = ImageModelProfiles.flux2Klein
        profile.output = .json(promptField: "prompt")
        let result = try await PromptEnhancer().enhance("a fox", profile: profile, task: .textToImage) { _ in "A fox." }
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.prompt, "a fox")
    }

    // MARK: - Sources

    func testVendorTextsAreIntactAndAttributed() {
        XCTAssertEqual(VendorPrompts.zImage.components(separatedBy: "{prompt}").count, 2, "one slot for the brief")
        XCTAssertTrue(VendorPrompts.zImage.hasPrefix("你是一位被关在逻辑牢笼里的幻视艺术家"))
        XCTAssertTrue(VendorPrompts.qwenImageEnglish.hasPrefix("You are a Prompt optimizer"))
        XCTAssertTrue(VendorPrompts.qwenImageEnglish.contains("less than 200 words"))
        XCTAssertTrue(VendorPrompts.qwenImageChinese.hasPrefix("你是一位Prompt优化师"))
        XCTAssertFalse(VendorPrompts.qwenImageEnglish.contains("{prompt}"))
        XCTAssertFalse(VendorPrompts.qwenImageChinese.contains("{prompt}"))
        for profile in ImageModelProfiles.all {
            if profile.source.verbatim {
                XCTAssertEqual(profile.source.license, "Apache-2.0", profile.id)
                XCTAssertTrue(profile.source.origin.contains("/blob/"), "\(profile.id) pins its source")
            } else {
                XCTAssertEqual(profile.source, .original, profile.id)
            }
        }
    }
}
