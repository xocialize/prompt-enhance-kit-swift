/// Enhance profiles for the Pixel Agency Image Engine's text-to-image models (AB-D-0155, phase E1). Text-only: edit
/// rewriters need to see the input image (E4), and structured formats (SenseNova's Render JSON, MOSS and Ming layouts,
/// Qwen-Image 2.1's `{rewritten_prompt, wh_ratio}`) come with E3.
///
/// FLUX 3 Klein has no profile here on purpose: BFL's own upsampler (a dedicated model) runs inside flux3-klein-swift.
public enum ImageModelProfiles {
    /// Z-Image and Z-Image Turbo, with Tongyi's own expander, verbatim. Their demo ships it switched off, so it's
    /// `optional`: `auto` leaves prompts alone.
    public static let zImage = EnhanceProfile(
        id: "z-image", version: 2, title: "Z-Image",
        models: ["z-image-turbo", "z-image"],
        policy: .optional,
        // The vendor substitutes the brief into the instruction and sends that as the system turn (app.py,
        // `APIPromptExpander.extend`). Its user turn is a single space; ours carries `zImageNudge`, in Chinese for a
        // brief with CJK ideographs (an English nudge pulled a Chinese brief's answer into English).
        instructions: [.textToImage: EnhanceInstructionSet(
            EnhanceInstruction(system: VendorPrompts.zImage, user: zImageNudge),
            chinese: EnhanceInstruction(system: VendorPrompts.zImage, user: zImageNudgeChinese))],
        output: .text(),
        passThrough: PassThroughRule(detailedAtWords: 80),
        backbone: .small,
        sampling: SamplingOverrides(temperature: 0.7, topP: 0.8, maxTokens: 768),
        source: ProfileSource(
            origin: "https://huggingface.co/spaces/Tongyi-MAI/Z-Image-Turbo/blob/768cb50d847cdbba97c89533ae976be69cf5a5b8/pe.py",
            license: "Apache-2.0", verbatim: true,
            adaptation: "None to the vendor's text. The vendor's user turn is a single space; since v2 it carries one "
                + "sentence of the kit's own (MIT), in English or, for a brief with CJK ideographs, Chinese, asking for "
                + "prose in the brief's language, not a tag list, and only what is in the image: on a 4B backbone the "
                + "expander answered a tag list and ended a rewrite with \"No text is present.\" (AB-R-0589). Sampling "
                + "(temperature 0.7, top-p 0.8) is the vendor's."),
        notes: "Tongyi's demo has this expander switched off, and Turbo already scores well on raw prompts. The vendor ran "
            + "it on qwen3-max; a small backbone may manage less of its reasoning step. Text to render goes in double "
            + "quotes; Z-Image's text encoder reads 512 tokens.")

    /// The user turn of `zImage`, in place of the vendor's single space: a nudge toward what the expander already asks
    /// for (an objective, concrete visual description), for a small backbone. The kit's own text, MIT.
    static let zImageNudge = "Answer in the language of the user's prompt, as flowing prose in complete sentences rather "
        + "than a comma-separated list of tags, and describe only what is in the image."

    /// `zImageNudge` for a brief with CJK ideographs, in Chinese. It names Chinese as the answer's language (with the
    /// vendor's single space, Qwen3.5-4B int4 answered 20 of 20 Chinese briefs in English) and asks not to say what is
    /// absent (a Chinese answer otherwise often closed with "画面中没有任何文字元素").
    static let zImageNudgeChinese = "请用用户输入 prompt 的语言作答（中文输入就用中文写），写成连贯、完整的句子，不要写成逗号分隔的"
        + "标签列表；只描述画面中存在的内容，不要写画面中没有什么。"

    /// Qwen-Image Flash, with Qwen-Image's own rewriter, verbatim: English and Chinese instructions chosen by the
    /// brief's script, one-line output, and Qwen's quality suffix. Qwen's example code rewrites every prompt, so
    /// it's `recommended`.
    public static let qwenImage = EnhanceProfile(
        id: "qwen-image", version: 1, title: "Qwen-Image",
        models: ["qwen-image-flash"],
        policy: .recommended,
        // The vendor's `api()` sends a generic system turn and puts the instruction and the brief in the user turn.
        instructions: [.textToImage: EnhanceInstructionSet(
            EnhanceInstruction(system: "You are a helpful assistant.",
                               user: VendorPrompts.qwenImageEnglish + "\n\nUser Input: {prompt}\n\n Rewritten Prompt:",
                               suffix: VendorPrompts.qwenImageMagicEnglish),
            chinese: EnhanceInstruction(system: "You are a helpful assistant.",
                                        user: VendorPrompts.qwenImageChinese + "\n\n用户输入：{prompt}\n改写输出：",
                                        suffix: VendorPrompts.qwenImageMagicChinese))],
        output: .text(singleLine: true),
        passThrough: PassThroughRule(detailedAtWords: 60),
        backbone: .small,
        sampling: SamplingOverrides(maxTokens: 512),
        source: ProfileSource(
            origin: "https://github.com/QwenLM/Qwen-Image/blob/3453042c9f35f284abce58c68302a1183f6b40f2/src/examples/tools/prompt_utils.py",
            license: "Apache-2.0", verbatim: true,
            adaptation: "The English suffix is joined with a space; the vendor appends it directly."),
        notes: "Flash is NVIDIA's distillation of Qwen-Image, trained on long English captions. A Chinese brief gets "
            + "Qwen's Chinese rewriter, which NVIDIA didn't evaluate on Flash. The vendor ran it on qwen-plus.")

    /// FLUX.2 [klein] 4B and its base tier. BFL publishes no enhancer; this is original text following its prompting
    /// guidance (prose rather than tags, the subject first, rendered text in quotes), leaning into what klein does
    /// well: legible text, exact counts and spatial relations (mlxengine-image PROMPT-ENHANCER-INTEGRATION.md §5.1).
    ///
    /// v2: v1's "Don't add text, logos or people the brief doesn't ask for" came back as a closing "No text, logos, or
    /// other people are present." (AB-R-0588, AB-R-0589), so the instruction no longer lists what to leave out, and asks
    /// for every sentence to describe something visible. On Qwen3.5-4B int4, 60 rewrites of 12 briefs: absence
    /// sentences 7 → 0, invented signs about as before (4, in scenes that carry them, such as a diner). "Put words in the
    /// image only when the brief asks for them" made both worse, so the text rule stays conditional.
    public static let flux2Klein = EnhanceProfile(
        id: "flux2-klein", version: 2, title: "FLUX.2 [klein]",
        models: ["klein-4b", "klein-4b-base"],
        policy: .recommended,
        instructions: [.textToImage: EnhanceInstructionSet(EnhanceInstruction(system: """
            You write prompts for FLUX.2 [klein], a text-to-image model that follows detailed natural-language \
            descriptions closely and renders legible text. Rewrite the user's brief as one paragraph of plain \
            descriptive prose, most important first: the main subject and what it is doing, then the setting, then \
            composition and camera (framing, angle, and lens or depth of field where it matters), then lighting, colour \
            palette and materials, then the style or medium. Keep every subject, number, colour, name and relationship \
            the brief gives, and make vague ones specific: exact counts, where each thing sits relative to the others, \
            concrete colours. When the brief asks for words in the image, write them exactly, inside double quotes, and \
            say where they appear and how they look (typeface, size, colour, the surface they're on); never translate \
            them. Every sentence must describe something visible in the image: never say what is absent, and never \
            close with a sentence such as "No text is present." End on a detail of the scene itself. Write 40 to 150 \
            words, with no lists, tags or quality keywords such as "8K" or "masterpiece". Output only the prompt, with \
            no preamble and no quotes around it.
            """))],
        output: .text(),
        passThrough: PassThroughRule(detailedAtWords: 60),
        backbone: .small,
        sampling: SamplingOverrides(maxTokens: 400),
        source: .original,
        notes: "BFL publishes no enhancer for FLUX.2 [klein]. The distilled tier ignores negative prompts; the base tier "
            + "(CFG) uses them, and proposing one is deferred (AB-T-0054 E2).")

    /// Mage-Flow and Mage-Flow Turbo. Its makers publish no enhancer, so this is general original guidance, and it's
    /// `optional`: `auto` leaves prompts alone.
    public static let mageFlow = EnhanceProfile(
        id: "mage-flow", version: 1, title: "Mage-Flow",
        models: ["mage-flow", "mage-flow-turbo"],
        policy: .optional,
        instructions: [.textToImage: EnhanceInstructionSet(EnhanceInstruction(system: """
            You write prompts for Mage-Flow, a text-to-image model that follows long, detailed descriptions and renders \
            English and Chinese text. Rewrite the user's brief as one detailed paragraph in the same language as the \
            brief. Cover, in order: the main subject and its action, the setting, composition and camera, lighting and \
            colour, materials and textures, and the style or medium. Keep every subject, count, colour, name and \
            spatial relationship the brief gives, and make vague details specific. When the brief asks for text in the \
            image, copy it exactly, inside double quotes, in its original language, and describe where it sits and its \
            typography. Don't add text the brief doesn't ask for. Write at most 200 words, as prose rather than a list \
            of tags. Output only the prompt, with no preamble.
            """))],
        output: .text(),
        passThrough: PassThroughRule(detailedAtWords: 60),
        backbone: .small,
        sampling: SamplingOverrides(maxTokens: 512),
        source: .original,
        notes: "Mage-Flow's makers publish no enhancer. The RL tier (CFG 5) uses negative prompts; Turbo ignores them.")

    /// Every image profile above.
    public static let all = [zImage, qwenImage, flux2Klein, mageFlow]
}

extension ProfileLibrary {
    /// The shipped profiles for the image engine's text-to-image models.
    public static func imageModels() -> ProfileLibrary { ProfileLibrary(ImageModelProfiles.all) }
}
