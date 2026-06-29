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
