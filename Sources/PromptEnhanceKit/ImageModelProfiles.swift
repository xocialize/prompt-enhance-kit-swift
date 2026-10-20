/// Enhance profiles for the Pixel Agency Image Engine's text-to-image models (AB-D-0155). Prose profiles came with E1;
/// SenseNova U1.5's Render JSON, a structured profile on a `large` backbone, with E3. Edit rewriters need to see the input
/// image (E4). Ming-Image's layers are defined (`mingImage`) but not shipped: they failed the E3 gate on Qwen3.5-9B.
/// MOSS-Image's layout (`moss`: its agent skill verbatim, with the skill's converter script ported) came with E3's second
/// part. Qwen-Image 2.1's `{rewritten_prompt, wh_ratio}` (its rewriter's text is under the Qwen Research licence) is still
/// to come.
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

    /// SenseNova U1.5 and its 8-step tiers, with SenseTime's own image prompt enhancer, verbatim: the brief compiled into
    /// Render JSON (subjects, scene, lighting, composition, style, camera, the visible copy, a canvas and a negative),
    /// which the model reads as its prompt; the vendor passes the compact JSON straight to inference. The vendor makes it
    /// the default step before inference, so it's `recommended` with no word limit: only a brief that is already JSON goes
    /// as typed. `canvas` names one of five 2K sizes (1:1 2048², 3:2 2496×1664, 2:3 1664×2496, 16:9 2720×1536, 9:16
    /// 1536×2720), read into `suggestedSize`; the vendor generates at it.
    public static let senseNova = EnhanceProfile(
        id: "sensenova-u1.5", version: 1, title: "SenseNova U1.5",
        models: ["sensenova-u1", "sensenova-u1-fast", "sensenova-u1-fast-v1"],
        policy: .recommended,
        // The vendor sends the text as the Responses API's `instructions` and the brief as its `input`.
        instructions: [.textToImage: EnhanceInstructionSet(EnhanceInstruction(system: VendorPrompts.senseNovaImagePE))],
        output: .json(layout: .compact),
        sizeFields: [["canvas", "resolution"], ["canvas", "aspect_ratio"]],
        passThrough: PassThroughRule(),
        backbone: .large,
        // The vendor's `max_output_tokens`; its prompt targets 1,100 to 1,500 output tokens.
        sampling: SamplingOverrides(maxTokens: 4096),
        source: ProfileSource(
            origin: "https://github.com/OpenSenseNova/SenseNova-U1/blob/a62fd54afed7a8d4c1cb4e10f0c39253d1be6fde/src/sensenova_u1_5/image_pe.py",
            license: "Apache-2.0", verbatim: true,
            adaptation: "None to the vendor's text (`IMAGE_PE_SYSTEM_PROMPT`). The vendor sends it as the Responses API's "
                + "`instructions` with the brief as `input`; here they're the system and user turns. Its optional web-search "
                + "addition isn't used. Like the vendor's `extract_json`, the answer is read from its first `{` to its last "
                + "`}` and written out compact, in the backbone's key order."),
        notes: "SenseTime recommends this step before every text-to-image run and ran it on gpt-5.6-terra; here it runs on "
            + "a local backbone of the large class. A rewrite is about 1,100 to 1,500 tokens of JSON. Edits have their own "
            + "rewriter, which needs to see the image (E4).")

    /// Ming-Image, with inclusionAI's own text-to-image rewriter, verbatim: the brief expanded into a Figma-style layer
    /// JSON (`canvas_settings`, then `layers` from background to top, each with normalised `coordinates` and hex
    /// `color_specs`), which the model reads as its prompt. The vendor runs it as an optional step outside inference, so
    /// it's `optional`: `auto` leaves prompts alone. The JSON is written out with two-space indentation, as the vendor's
    /// example prompts are.
    ///
    /// **Not in `all`, so not in `imageModels()`.** On Qwen3.5-9B int4 it failed the E3 gate (prompt-enhance-e2e
    /// `--structured`, 6 briefs × 2 seeds): 3 of 12 answers in the vendor's format at temperature 0.7, 6 of 12 at 0.3. The
    /// backbone anchored layers at their top-left corner rather than their centre (`cx: 0.000, cy: 0.000, w: 1.000`),
    /// wrote coordinates without three decimals, and repeated a quoted string. The vendor suggests far larger rewriters
    /// (Ling-3.0-flash-VL, qwen3.8-27B). A host that has one can register it.
    public static let mingImage = EnhanceProfile(
        id: "ming-image", version: 1, title: "Ming-Image",
        models: ["ming-image"],
        policy: .optional,
        instructions: [.textToImage: EnhanceInstructionSet(EnhanceInstruction(system: VendorPrompts.mingImageRewriter))],
        output: .json(layout: .pretty),
        sizeFields: [["canvas_settings", "aspect_ratio"]],
        passThrough: PassThroughRule(),
        backbone: .large,
        sampling: SamplingOverrides(maxTokens: 3072),
        source: ProfileSource(
            origin: "https://github.com/inclusionAI/Ming-Image/blob/578e21e081a7cd385b6c79e36df7e419155681b1/assets/t2i_rewriter_system_prompt.txt",
            license: "MIT", verbatim: true,
            adaptation: "None to the vendor's text, without the file's final newline. The vendor doesn't say how to send it; "
                + "here it's the system turn, with the brief as the user turn."),
        notes: "inclusionAI suggests Ling-3.0-flash-VL or qwen3.8-27B as the rewriter; here it runs on a local backbone of "
            + "the large class. The rewriter lays out a 1:1 canvas unless told otherwise, so pass the target size. Hex "
            + "codes and JSON quote marks in the prompt can show up in renders as glyphs (ming-image-oracle GATE-RESULTS).")

    /// MOSS-Image SFT and Base, with OpenMOSS's own prompt-enhancer skill, verbatim: the brief laid out as a Layout draft
    /// (`summary`, then `items`, each a label, a caption, any literal text and a pixel box), which the skill's own script
    /// compiles (`AnswerCompiler.mossImageLayout`, ported) into the JSON the model reads, boxes centred on the canvas. A
    /// layout is for one canvas, so a host passes the target size and generates at exactly `EnhanceResult.canvas`. The
    /// vendor ships the skill as an optional agent tool and calls layout prompts experimental, so it's `optional`: `auto`
    /// leaves prompts alone.
    ///
    /// The skill chooses between a caption and a Layout. This profile always asks for a Layout, which the skill honours
    /// when asked; a caption draft still compiles, to its caption.
    public static let moss = EnhanceProfile(
        id: "moss-image", version: 3, title: "MOSS-Image",
        models: ["moss-image-sft", "moss-image-base"],
        policy: .optional,
        // The agent the skill is written for reads SKILL.md, and references/layout.md before a Layout draft.
        instructions: [.textToImage: EnhanceInstructionSet(EnhanceInstruction(system: mossSystem, user: mossUser))],
        output: .json(layout: .compact),
        compiler: .mossImageLayout,
        passThrough: PassThroughRule(),
        backbone: .large,
        // The vendor sets no sampler (its agent is GPT-6-family). Measured on Qwen3.5-9B int4 (prompt-enhance-e2e
        // `--structured`, v2): at 0.7, 12 of 16 drafts compiled with every quoted string whole; at 0.3, 24 of 24.
        sampling: SamplingOverrides(temperature: 0.3, maxTokens: 4096),
        source: ProfileSource(
            origin: "https://github.com/OpenMOSS/MOSS-Image/tree/6f9aabb9db61576838287a18b046383b5402fe26/skills/moss-image-prompt-enhancer",
            license: "Apache-2.0", verbatim: true,
            adaptation: "None to the vendor's texts (SKILL.md and references/layout.md). The skill is an agent's: it reads both, "
                + "writes a pixel draft to a file and runs scripts/compile_prompt.py on it. Here both texts are the system "
                + "turn, joined by a line of the kit's own (MIT). The user turn is the kit's own too: it asks for a Layout, "
                + "says there are no tools and the answer is the draft, puts each string the brief quotes in one text item "
                + "(v1 split \"LATTE 4.50\" into \"LATTE\" and \"4.50\" on Qwen3.5-9B) and gives no other item a `text` "
                + "(an empty one on an object was v2's commonest rejected draft), and carries the brief and the target "
                + "resolution. The script is ported to Swift (`MOSSLayout`) and run on the answer, with its checks, its "
                + "rounding and its compact output; a layout for another canvas than the target fails. A draft the script "
                + "rejects goes back to the backbone once with the script's message, as the skill's agent would fix and rerun "
                + "it (v1 lost 2 of 16 drafts to an empty `text` and a `panel` label)."),
        notes: "OpenMOSS wrote the skill for GPT-6-family agents; here it runs on a local backbone of the large class. A layout "
            + "is laid out in the pixels of one canvas and is only right at that size, so the image runs at the size the "
            + "enhancer was told. The vendor's guide calls layout prompts experimental; MOSS-Image reads plain captions too.")

    /// The system turn of `moss`: the skill, then the reference it says to read before a Layout draft, as an agent would
    /// have them. The joining line is the kit's own, MIT.
    static let mossSystem = VendorPrompts.mossImageSkill + "\n\nThe skill's file references/layout.md:\n\n"
        + VendorPrompts.mossImageLayoutReference

    /// The user turn of `moss`, in place of an agent's tools: what to answer with. The kit's own text, MIT. The kit adds
    /// the target resolution after it.
    static let mossUser = "Use the moss-image-prompt-enhancer skill above to write a Layout for the image idea below. You "
        + "have no file or shell tools here, so save and run nothing: answer with the Layout draft itself and nothing else, "
        + "the readable JSON object with `width`, `height`, `bbox_coord_space` \"abs\", `bbox_format` \"xyxy\", `summary` "
        + "and `items`, its boxes in actual pixels from the canvas's top-left. The host compiles it by the bundled script's "
        + "rules. Use the target resolution, when one is given, as `width` and `height`. Put each string the idea quotes "
        + "in one text item's `text`, exactly as quoted, and give no other item a `text` field.\n\nImage idea: {prompt}"

    /// The shipped image profiles: every one above except `mingImage`.
    public static let all = [zImage, qwenImage, flux2Klein, mageFlow, senseNova, moss]
}

extension ProfileLibrary {
    /// The shipped profiles for the image engine's text-to-image models.
    public static func imageModels() -> ProfileLibrary { ProfileLibrary(ImageModelProfiles.all) }
}
