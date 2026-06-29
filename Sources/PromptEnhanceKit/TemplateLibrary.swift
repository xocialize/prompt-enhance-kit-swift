import MLXToolKit

/// Registry of enhance templates keyed by `(Capability, EnhanceTask)`. Seeded with neutral
/// image + video templates (UPE0); `register` adds or overrides one (e.g. to drop in a
/// model-specific profile). Backbone-agnostic — holds only text.
public struct TemplateLibrary: Sendable {
    private struct Key: Hashable { let capability: Capability; let task: EnhanceTask }
    private var templates: [Key: PromptEnhanceTemplate]

    /// `seeded` (default) installs the built-in image/video templates; pass `false` for an empty
    /// library you fill yourself.
    public init(seeded: Bool = true) {
        templates = seeded ? Self.defaults : [:]
    }

    public func template(for capability: Capability, task: EnhanceTask) -> PromptEnhanceTemplate? {
        templates[Key(capability: capability, task: task)]
    }

    public mutating func register(_ template: PromptEnhanceTemplate,
                                  capability: Capability, task: EnhanceTask) {
        templates[Key(capability: capability, task: task)] = template
    }

    // MARK: - Seed templates (UPE0)

    private static let imageT2I = PromptEnhanceTemplate(system: """
    You are a prompt enhancer for a text-to-image model. Rewrite the user's brief into ONE vivid, \
    concrete visual description in a single paragraph: name the subject and setting first, then \
    composition, lighting, color palette, mood, and rendering style, with specific tangible detail. \
    Preserve the user's intent and any named subjects. Do not add people or written text unless the \
    brief asks for them. Output ONLY the enhanced prompt — no preamble, quotes, or explanation.
    """)

    private static let videoT2V = PromptEnhanceTemplate(system: """
    You are a prompt enhancer for a text-to-video model. Expand the user's brief into ONE vivid \
    cinematic description in a single paragraph: the subject and its action, the camera (shot size, \
    angle, and movement), lighting and time of day, atmosphere and mood, and how the scene and its \
    motion evolve across the shot. Preserve the user's intent and any named subjects. Output ONLY the \
    enhanced prompt — no preamble, quotes, or explanation.
    """)

    private static let videoI2V = PromptEnhanceTemplate(system: """
    You are a prompt enhancer for an image-to-video model. The user gives a brief instruction for \
    animating a starting image (the first frame). Describe how that scene comes to life going forward: \
    the motion of its subjects, the camera movement, and how lighting and atmosphere evolve — while \
    preserving the subject, composition, and style of the given frame. Output ONLY the enhanced \
    prompt — no preamble, quotes, or explanation.
    """)

    private static let defaults: [Key: PromptEnhanceTemplate] = [
        Key(capability: .textToImage, task: .textToImage): imageT2I,
        Key(capability: .textToVideo, task: .textToVideo): videoT2V,
        Key(capability: .textToVideo, task: .imageToVideo): videoI2V,
    ]
}
