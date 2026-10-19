import XCTest
import MLXToolKit
import PromptEnhanceKit  // not @testable: these tests hold the API a host sees

/// v0.5.1: the pass-through decision is public, so a host can tell whether `enhance` will call the backbone before it
/// loads one (AB-A-0195).
final class PublicDecisionTests: XCTestCase {

    func testAHostCanAskBeforeLoadingABackbone() {
        let zImage = ImageModelProfiles.zImage
        XCTAssertEqual(PromptEnhancer.decision("a red fox in snow", profile: zImage, task: .textToImage),
                       .notRecommended, "auto is the default mode")
        XCTAssertNil(PromptEnhancer.decision("a red fox in snow", profile: zImage, task: .textToImage, mode: .always))
        XCTAssertNil(PromptEnhancer.decision("a lighthouse at dusk", profile: ImageModelProfiles.qwenImage,
                                             task: .textToImage))
        XCTAssertEqual(PromptEnhancer.decision(#"{"caption": "a poster"}"#, profile: ImageModelProfiles.qwenImage,
                                               task: .textToImage, mode: .always), .passedThrough)
        XCTAssertEqual(PromptEnhancer.decision("x", profile: ImageModelProfiles.qwenImage, task: .imageEdit),
                       .noInstruction)
    }

    /// `nil` exactly when `enhance` calls the backbone; otherwise the outcome `enhance` returns.
    func testTheDecisionMatchesWhatEnhanceDoes() async throws {
        let long = Array(repeating: "detail", count: 90).joined(separator: " ")
        let briefs = ["a red fox in snow", long, #"{"caption": "a poster"}"#, "一只可爱的小猫坐在花园里"]
        for profile in ImageModelProfiles.all {
            for task in [EnhanceTask.textToImage, .imageEdit] {
                for mode in EnhanceMode.allCases {
                    for brief in briefs {
                        let decided = PromptEnhancer.decision(brief, profile: profile, task: task, mode: mode)
                        let called = Called()
                        let result = try await PromptEnhancer().enhance(brief, profile: profile, task: task,
                                                                        mode: mode) { _ in
                            called.value = true
                            return "A rewrite."
                        }
                        let label = "\(profile.id) \(task) \(mode) \(brief.prefix(20))"
                        XCTAssertEqual(called.value, decided == nil, label)
                        XCTAssertEqual(result.outcome, decided ?? .enhanced, label)
                        if decided != nil { XCTAssertEqual(result.prompt, brief, label) }
                    }
                }
            }
        }
    }
}

private final class Called: @unchecked Sendable {
    var value = false
}
