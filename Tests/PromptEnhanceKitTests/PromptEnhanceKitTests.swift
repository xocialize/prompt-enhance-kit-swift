import XCTest
import MLXToolKit
@testable import PromptEnhanceKit

final class PromptEnhanceKitTests: XCTestCase {

    // MARK: - Template library

    func testSeededLibraryHasImageAndVideoTemplates() {
        let lib = TemplateLibrary()
        XCTAssertNotNil(lib.template(for: .textToImage, task: .textToImage), "image t2i seed missing")
        XCTAssertNotNil(lib.template(for: .textToVideo, task: .textToVideo), "video t2v seed missing")
        XCTAssertNotNil(lib.template(for: .textToVideo, task: .imageToVideo), "video i2v seed missing")
    }

    func testUnregisteredComboReturnsNil() {
        let lib = TemplateLibrary()
        // characterReplacement isn't seeded in UPE0.
        XCTAssertNil(lib.template(for: .characterAnimation, task: .characterReplacement))
    }

    func testRegisterOverrides() {
        var lib = TemplateLibrary(seeded: false)
        let t = PromptEnhanceTemplate(system: "custom")
        lib.register(t, capability: .textToVideo, task: .textToVideo)
        XCTAssertEqual(lib.template(for: .textToVideo, task: .textToVideo), t)
    }

    func testNeedsVisionFlag() {
        XCTAssertFalse(EnhanceTask.textToImage.needsVision)
        XCTAssertFalse(EnhanceTask.textToVideo.needsVision)
        XCTAssertTrue(EnhanceTask.imageToVideo.needsVision)
        XCTAssertTrue(EnhanceTask.characterReplacement.needsVision)
    }

    // MARK: - LTX-2.3 profile (UPE1-LTX)

    func testLTXProfileOverridesVideoTemplatesOnly() {
        let lib = TemplateLibrary.ltxVideo()
        XCTAssertEqual(lib.template(for: .textToVideo, task: .textToVideo), LTXVideoProfile.textToVideo)
        XCTAssertEqual(lib.template(for: .textToVideo, task: .imageToVideo), LTXVideoProfile.imageToVideo)
        // Image seed untouched.
        XCTAssertEqual(lib.template(for: .textToImage, task: .textToImage),
                       TemplateLibrary().template(for: .textToImage, task: .textToImage))
    }

    func testLTXRegisterOntoExistingLibrary() {
        var lib = TemplateLibrary()
        let neutral = lib.template(for: .textToVideo, task: .textToVideo)
        lib.registerLTXVideoProfile()
        XCTAssertNotEqual(lib.template(for: .textToVideo, task: .textToVideo), neutral)
        XCTAssertEqual(lib.template(for: .textToVideo, task: .textToVideo), LTXVideoProfile.textToVideo)
    }

    // MARK: - Request shape

    func testMakeRequestIsPromptEnhanceModeWithSystemAndUser() {
        let enhancer = PromptEnhancer()
        let template = PromptEnhanceTemplate(system: "SYS")
        let req = enhancer.makeRequest("a red fox", template: template)
        XCTAssertEqual(req.mode, .promptEnhance)
        XCTAssertEqual(req.messages.count, 2)
        XCTAssertEqual(req.messages[0].role, .system)
        XCTAssertEqual(req.messages[0].content, "SYS")
        XCTAssertEqual(req.messages[1].role, .user)
        XCTAssertEqual(req.messages[1].content, "a red fox")
    }

    func testMakeRequestAppendsTargetSizeToUserTurn() {
        let req = PromptEnhancer().makeRequest("a city", template: PromptEnhanceTemplate(system: "S"),
                                               targetSize: (1024, 768))
        XCTAssertTrue(req.messages[1].content.contains("1024x768"), "size hint missing: \(req.messages[1].content)")
    }

    func testMakeRequestAppendsTargetDurationToUserTurn() {
        let req = PromptEnhancer().makeRequest("a city", template: PromptEnhanceTemplate(system: "S"),
                                               targetDuration: 121.0 / 24.0)  // 121f @ 24fps → ~5s
        XCTAssertTrue(req.messages[1].content.contains("~5 seconds"), "duration hint missing: \(req.messages[1].content)")
    }

    func testMakeRequestOmitsNonPositiveDuration() {
        let req = PromptEnhancer().makeRequest("a city", template: PromptEnhanceTemplate(system: "S"),
                                               targetDuration: 0)
        XCTAssertEqual(req.messages[1].content, "a city")
    }

    // Contract 1.33.0 (`LLMParameters.seed`) reached this kit with NO code change: `parameters`
    // is caller-supplied and `makeRequest` passes it through verbatim, so a caller pins the
    // enhancement by constructing the enhancer with a seed. AB-R-0079 audited that as the reason
    // the fix was two edits in two other repos and none here — this test is what keeps the claim
    // true. Enhancement rewrites the prompt a generation then consumes, so an unpinnable enhancer
    // makes the whole run irreproducible even with the generation seed fixed.
    func testMakeRequestForwardsCallerSuppliedSeedVerbatim() {
        let template = PromptEnhanceTemplate(system: "SYS")

        // Default enhancer: unpinned, exactly as before 1.33.0 — nil means system entropy.
        XCTAssertNil(PromptEnhancer().makeRequest("a red fox", template: template).parameters.seed)

        // Pinned enhancer: the seed rides the canonical request untouched, and no metaData
        // dialect is involved (the LFM-style `metaData["seed"]` route this kit could never use).
        let pinned = PromptEnhancer(library: .ltxVideo(),
                                    parameters: LLMParameters(temperature: 0.7, maxTokens: 512,
                                                              seed: 10))
        let req = pinned.makeRequest("a red fox", template: template)
        XCTAssertEqual(req.parameters.seed, 10)
        XCTAssertEqual(req.parameters.temperature, 0.7)
        XCTAssertEqual(req.parameters.maxTokens, 512)
        XCTAssertTrue(req.metaData.isEmpty)
    }

    // MARK: - Host-provided chat model (`generate:` overload, BRIDGE-LTX-003)

    func testGenerateOverloadReceivesTemplateSystemAndHintedUserTurn() async {
        actor Captured { var system = ""; var user = ""; func set(_ s: String, _ u: String) { system = s; user = u } }
        let captured = Captured()
        let out = await PromptEnhancer(library: .ltxVideo()).enhance(
            "a red fox", capability: .textToVideo, task: .textToVideo,
            targetSize: (704, 512), targetDuration: 5) { system, user in
                await captured.set(system, user)
                return "enhanced"
            }
        XCTAssertEqual(out, "enhanced")
        let system = await captured.system
        let user = await captured.user
        XCTAssertEqual(system, LTXVideoProfile.textToVideo.system)
        XCTAssertTrue(user.hasPrefix("a red fox"))
        XCTAssertTrue(user.contains("704x512"))
        XCTAssertTrue(user.contains("~5 seconds"))
    }

    func testGenerateOverloadFallsBackOnThrowEmptyAndNoTemplate() async {
        struct Boom: Error {}
        let enhancer = PromptEnhancer()
        let threw = await enhancer.enhance("keep me", capability: .textToVideo, task: .textToVideo) {
            (_: String, _: String) in throw Boom()
        }
        XCTAssertEqual(threw, "keep me")
        let empty = await enhancer.enhance("keep me", capability: .textToVideo, task: .textToVideo) {
            (_: String, _: String) in "   "
        }
        XCTAssertEqual(empty, "keep me")
        let none = await enhancer.enhance("keep me", capability: .characterAnimation, task: .characterReplacement) {
            (_: String, _: String) in "should not be used"
        }
        XCTAssertEqual(none, "keep me")
    }

    // MARK: - Enhance + the (critical) raw-fallback contract

    func testEnhanceReturnsRunnerText() async {
        let out = await PromptEnhancer().enhance("brief", capability: .textToVideo, task: .textToVideo) { _ in
            "  a cinematic enhanced prompt  "  // trimmed by the enhancer
        }
        XCTAssertEqual(out, "a cinematic enhanced prompt")
    }

    func testEnhanceFallsBackToRawWhenRunnerThrows() async {
        struct Boom: Error {}
        let out = await PromptEnhancer().enhance("keep me", capability: .textToVideo, task: .textToVideo) { _ in
            throw Boom()
        }
        XCTAssertEqual(out, "keep me", "must fall back to the raw prompt on runner error")
    }

    func testEnhanceFallsBackToRawWhenResultEmpty() async {
        let out = await PromptEnhancer().enhance("keep me", capability: .textToImage, task: .textToImage) { _ in
            "   "  // whitespace-only → empty after trim
        }
        XCTAssertEqual(out, "keep me", "must fall back to the raw prompt on empty result")
    }

    func testEnhanceFallsBackToRawWhenNoTemplate() async {
        actor Flag { var ran = false; func set() { ran = true } }
        let flag = Flag()
        let out = await PromptEnhancer().enhance("keep me", capability: .characterAnimation, task: .characterReplacement) { _ in
            await flag.set()
            return "should not be used"
        }
        XCTAssertEqual(out, "keep me", "no template → raw prompt, no run")
        let ran = await flag.ran
        XCTAssertFalse(ran, "runner must not be invoked when there is no template")
    }
}
