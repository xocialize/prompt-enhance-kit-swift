import MLXToolKit

/// The task a prompt is being enhanced FOR — it selects the template. String-backed and
/// extensible so a consumer can register its own task. Pairs with a `Capability`
/// (`textToImage` / `textToVideo` / `characterAnimation`) to key the `TemplateLibrary`.
public struct EnhanceTask: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    // Image (capability `.textToImage`)
    public static let textToImage: EnhanceTask = "t2i"
    public static let imageEdit: EnhanceTask = "i2i"
    public static let referenceToImage: EnhanceTask = "r2i"
    // Video (capability `.textToVideo`)
    public static let textToVideo: EnhanceTask = "t2v"
    public static let imageToVideo: EnhanceTask = "i2v"
    public static let videoEdit: EnhanceTask = "v2v"
    public static let referenceToVideo: EnhanceTask = "r2v"
    // Character animation (capability `.characterAnimation`)
    public static let characterReplacement: EnhanceTask = "replacement"

    /// Whether the task needs visual context (a ref image / video frames) → a vision-capable
    /// backbone. Text-only tasks run on ANY chat LLM the host provides — including a pipeline's
    /// own text encoder when it is an instruction-tuned LLM; no specific model package is implied
    /// or required. (Vision wiring = UPE2.)
    public var needsVision: Bool {
        switch self {
        case .imageEdit, .referenceToImage, .imageToVideo, .videoEdit,
             .referenceToVideo, .characterReplacement:
            return true
        default:
            return false
        }
    }
}
