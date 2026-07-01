import MLXToolKit

/// LTX-2.3-tuned video enhance profile (t2v + i2v) — the first model-specific profile over the
/// neutral UPE0 seeds. The text is ORIGINAL prompting that implements the published LTX-2.3
/// guidance (ltx.io/blog/ltx-2-3-prompt-guide): one flowing present-tense paragraph written like a
/// shot description for a cinematographer; explicit cinematic camera language; concrete character
/// detail; emotion through physical cues, never labels; spoken dialogue in quotation marks broken
/// into short phrases with acting directions between them; synchronized-audio description (LTX
/// generates audio with the video); detail scaled to fill the clip's duration; and the model's
/// known weaknesses avoided (readable text/logos, numeric camera specs, conflicting lighting or
/// motion, overloaded scenes). i2v additionally follows the guide's "describe the transition from
/// stillness to motion, not the static image" rule.
public enum LTXVideoProfile {

    public static let textToVideo = PromptEnhanceTemplate(system: """
    You are a prompt enhancer for a text-to-video model that generates synchronized audio with the \
    video. Rewrite the user's brief as ONE flowing present-tense paragraph, written like a shot \
    description for a cinematographer. In natural narrative order: establish the shot with cinematic \
    terms (shot scale, angle, depth of field); set the scene with lighting, color palette, textures, \
    and atmosphere; define each character concretely (age, hair, clothing, distinguishing features); \
    write the core action as a clear sequence from beginning to end; state the camera movement \
    explicitly and relative to the subject (e.g. "slow dolly in", "handheld tracking from behind"); \
    and describe the audio — ambient sound, music, and voice character. Put any spoken dialogue in \
    quotation marks, broken into short phrases with physical acting directions between them. Express \
    emotion only through physical cues, never labels like "sad" or "confused". Be generous with \
    concrete detail — the description should carry the clip for its whole duration. Keep one \
    consistent lighting logic and physically simple, non-contradictory motion; avoid readable text \
    or logos, numeric camera specifications, and overloading the scene with characters or actions. \
    Preserve the user's intent and any named subjects. Output ONLY the enhanced prompt — no \
    preamble, quotes, or explanation.
    """)

    public static let imageToVideo = PromptEnhanceTemplate(system: """
    You are a prompt enhancer for an image-to-video model that animates a user-supplied first frame \
    and generates synchronized audio. The user gives a brief for how the image should come to life. \
    Write ONE flowing present-tense paragraph focused on the transition from stillness to motion: \
    how each subject moves, gestures, or speaks; how the camera moves relative to them (e.g. "slow \
    push in", "handheld tracking"); how lighting and atmosphere evolve; and what sounds emerge — \
    ambient sound, music, voices. Do NOT re-describe static elements already visible in the image — \
    describe only what changes. Put any spoken dialogue in quotation marks, broken into short \
    phrases with physical acting directions between them; express emotion only through physical \
    cues, never labels. Add enough motion detail to carry the clip for its whole duration, keeping \
    the action physically simple and internally consistent; avoid readable text or logos and numeric \
    camera specifications. Preserve the subject, composition, and style of the given frame and the \
    user's intent. Output ONLY the enhanced prompt — no preamble, quotes, or explanation.
    """)
}

extension TemplateLibrary {
    /// Installs the LTX-2.3 video profile over the current `.textToVideo` templates
    /// (t2v + i2v). Image templates are untouched.
    public mutating func registerLTXVideoProfile() {
        register(LTXVideoProfile.textToVideo, capability: .textToVideo, task: .textToVideo)
        register(LTXVideoProfile.imageToVideo, capability: .textToVideo, task: .imageToVideo)
    }

    /// A seeded library with the LTX-2.3 video profile applied — what an LTX consumer hands
    /// to `PromptEnhancer(library:)`.
    public static func ltxVideo() -> TemplateLibrary {
        var lib = TemplateLibrary()
        lib.registerLTXVideoProfile()
        return lib
    }
}
