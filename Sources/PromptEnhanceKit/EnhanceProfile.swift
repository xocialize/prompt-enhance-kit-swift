import MLXToolKit

/// How one model wants its prompts enhanced: the instruction per task, how to read the answer, when to leave a prompt
/// alone, and where the instruction text came from. Profiles are DATA, keyed by the model ids they serve
/// (`ProfileLibrary`), so a host picks the profile for the model it's about to run and the kit does the rest.
///
/// A profile is the per-model counterpart of a `PromptEnhanceTemplate` (which stays as the neutral, model-agnostic
/// layer). Where a vendor publishes its own enhancer prompt under a licence that allows reuse, the profile carries it
/// verbatim and says so in `source`; otherwise the instruction is original text implementing the vendor's guidance.
public struct EnhanceProfile: Sendable, Equatable, Identifiable {
    /// A stable id, e.g. `qwen-image`. Recorded in results with `version`, so a host's provenance names exactly which
    /// instruction rewrote a prompt.
    public var id: String
    /// Bumped whenever the instruction text or output handling changes.
    public var version: Int
    public var title: String
    /// The model ids this profile serves (the engine catalog's ids, e.g. `z-image-turbo`).
    public var models: [String]
    /// What the model's makers say about enhancement; `auto` mode acts on it.
    public var policy: EnhancePolicy
    /// The instruction for each task the profile covers. A task without one is passed through as typed.
    public var instructions: [EnhanceTask: EnhanceInstructionSet]
    public var output: EnhanceOutput
    /// Where a JSON answer suggests the image's size: key paths to strings such as `"2048 x 2048"`, `"16:9"` or
    /// `"1:1, 2048 × 2048 px"` (SenseNova's `canvas`, Ming's `canvas_settings.aspect_ratio`), read in order into
    /// `EnhanceResult.suggestedSize`. Empty for text profiles.
    public var sizeFields: [[String]]
    /// The vendor's own code, run on a JSON answer before it becomes the prompt (MOSS-Image's layout compiler); nil for
    /// none. A compiled layout is laid out for one canvas (`laysOutCanvas`).
    public var compiler: AnswerCompiler?
    public var passThrough: PassThroughRule
    /// What kind of LLM can run this profile well; the host picks the package.
    public var backbone: BackboneClass
    /// Sampler overrides for this profile (the vendor's own settings, or the text encoder's token budget). `nil`
    /// fields keep the enhancer's `parameters`; the seed is always the caller's.
    public var sampling: SamplingOverrides
    /// Where the instruction text came from, and under what licence.
    public var source: ProfileSource
    /// Anything a host or operator should know (shown on model cards).
    public var notes: String?

    public init(id: String, version: Int, title: String, models: [String], policy: EnhancePolicy,
                instructions: [EnhanceTask: EnhanceInstructionSet], output: EnhanceOutput = .text(),
                sizeFields: [[String]] = [], compiler: AnswerCompiler? = nil,
                passThrough: PassThroughRule = PassThroughRule(), backbone: BackboneClass = .small,
                sampling: SamplingOverrides = SamplingOverrides(), source: ProfileSource, notes: String? = nil) {
        self.id = id; self.version = version; self.title = title; self.models = models; self.policy = policy
        self.instructions = instructions; self.output = output; self.sizeFields = sizeFields; self.compiler = compiler
        self.passThrough = passThrough; self.backbone = backbone; self.sampling = sampling; self.source = source
        self.notes = notes
    }

    /// Whether the rewrite is laid out for one pixel canvas (a MOSS-Image layout's boxes are in its pixels): a host
    /// always passes `targetSize`, and generates at exactly `EnhanceResult.canvas`.
    public var laysOutCanvas: Bool { compiler?.laysOutCanvas ?? false }
}

/// A vendor's post-processing of its enhancer's answer, ported from the vendor's code (`EnhanceProfile.compiler`).
public enum AnswerCompiler: String, Sendable, Equatable, CaseIterable {
    /// MOSS-Image's `compile_prompt.py` (its prompt-enhancer skill's script, Apache-2.0): a Layout draft with pixel boxes
    /// from the canvas's top-left (`abs`, `xyxy`, its `width` and `height`) becomes the one-line JSON the model reads,
    /// boxes as whole pixels centred on the canvas (`abs_centralized`, `yxyx`) and no canvas; a caption draft becomes its
    /// caption. A draft the script rejects fails. The layout's canvas is `EnhanceResult.canvas`, and must be the target
    /// size when one was passed.
    case mossImageLayout

    /// Whether the compiled prompt is laid out for the canvas the draft names.
    public var laysOutCanvas: Bool {
        switch self {
        case .mossImageLayout: true
        }
    }

    /// What follows the user turn when the backbone is asked to fix a rejected draft. The kit's own text, MIT.
    func retryTurn(draft: String, message: String) -> String {
        switch self {
        case .mossImageLayout:
            "Your draft was:\n\n\(draft)\n\ncompile_prompt.py rejected it: \(message)\n\nFix the draft and answer with the "
                + "whole corrected draft, and nothing else. Leave a field out rather than empty (an item with no visible "
                + "wording has no `text`), use only the fields references/layout.md lists, and give every box x_min < x_max "
                + "and y_min < y_max inside the canvas."
        }
    }
}

/// What a model's makers say about prompt enhancement.
public enum EnhancePolicy: String, Sendable, Equatable, CaseIterable {
    /// The model degrades badly without it (FLUX 3 Klein's upsampler). `auto` always enhances.
    case required
    /// The vendor's own demo or guide rewrites prompts. `auto` enhances a brief that isn't already detailed.
    case recommended
    /// Available, but not the vendor's default. `auto` leaves prompts alone; `always` enhances.
    case optional
}

/// One task's instruction, with an optional Chinese variant for briefs written in Chinese (as Qwen-Image's own
/// rewriter chooses by script). `{prompt}` in either turn is replaced by the brief.
public struct EnhanceInstructionSet: Sendable, Equatable {
    public var standard: EnhanceInstruction
    /// Used when the brief contains CJK ideographs, if present.
    public var chinese: EnhanceInstruction?

    public init(_ standard: EnhanceInstruction, chinese: EnhanceInstruction? = nil) {
        self.standard = standard
        self.chinese = chinese
    }
}

/// The turns sent to the LLM, and what's appended to its answer.
public struct EnhanceInstruction: Sendable, Equatable {
    /// The system turn. `nil` sends none (a dedicated enhancer that brings its own instruction).
    public var system: String?
    /// The user turn. `{prompt}` is replaced by the brief; the default is the brief alone.
    public var user: String
    /// Appended to the rewritten prompt (a vendor's quality suffix, e.g. Qwen-Image's "magic" words).
    public var suffix: String?

    public init(system: String?, user: String = "{prompt}", suffix: String? = nil) {
        self.system = system
        self.user = user
        self.suffix = suffix
    }
}

/// How the LLM's answer becomes the prompt.
public enum EnhanceOutput: Sendable, Equatable {
    /// Free text. `singleLine` joins lines with spaces (Qwen-Image's rewriter does).
    case text(singleLine: Bool = false)
    /// JSON, constrained by the backbone where it supports structured output (contract 1.16.0). `promptField` names the
    /// top-level string to use as the prompt; `nil` uses the whole JSON value, written out as `layout` says, for formats
    /// the image model reads as JSON (layouts, Render JSON). Other top-level scalars come back in `EnhanceResult.fields`
    /// (e.g. `wh_ratio`), for the host to act on. An answer with prose around its object is read from the first `{` to
    /// the last `}`, as SenseNova's own enhancer does.
    case json(schema: String? = nil, promptField: String? = nil, layout: JSONLayout = .compact)
}

/// How a whole-JSON prompt is written out. Both keep the backbone's key order (vendors pass their enhancer's JSON as it
/// came, and a model may read the order: subjects before scene, background layers first) and its characters unescaped.
public enum JSONLayout: String, Sendable, Equatable, CaseIterable {
    /// No whitespace outside strings, like Python's `json.dumps(..., separators=(",", ":"))` (SenseNova's enhancer).
    case compact
    /// Two-space indentation, `": "` after keys, like `json.dumps(..., indent=2)` (Ming-Image's reference prompts).
    case pretty
}

/// When a prompt goes to the image model as typed.
public struct PassThroughRule: Sendable, Equatable {
    /// In `auto` mode, a brief with at least this many words is already detailed and isn't rewritten. CJK text counts
    /// one word per two ideographs.
    public var detailedAtWords: Int?
    /// A brief that is already JSON (a layout, Render JSON, a box table) is never rewritten.
    public var structured: Bool

    public init(detailedAtWords: Int? = nil, structured: Bool = true) {
        self.detailedAtWords = detailedAtWords
        self.structured = structured
    }
}

/// The kind of LLM a profile needs. Measured choices live in the host; this is the floor.
public enum BackboneClass: String, Sendable, Equatable, CaseIterable {
    /// A small text model (a few billion parameters) rewrites prose well enough.
    case small
    /// Long or structured output (Render JSON, layouts) needs a larger model.
    case large
    /// The task needs to see the input images (edit rewriters): a vision-language model.
    case vision
}

/// Per-profile sampler settings, applied over the enhancer's `parameters`.
public struct SamplingOverrides: Sendable, Equatable {
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?

    public init(temperature: Double? = nil, topP: Double? = nil, maxTokens: Int? = nil) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
    }

    func applied(to base: LLMParameters) -> LLMParameters {
        LLMParameters(temperature: temperature ?? base.temperature, topP: topP ?? base.topP,
                      maxTokens: maxTokens ?? base.maxTokens, stop: base.stop, seed: base.seed)
    }
}

/// Where a profile's instruction text came from.
public struct ProfileSource: Sendable, Equatable {
    /// A URL or reference for the text (or "original" for text written here).
    public var origin: String
    /// The SPDX id of the text's licence (the kit's own MIT for original text).
    public var license: String
    /// Whether the instruction is the vendor's text unchanged.
    public var verbatim: Bool
    /// What was changed or added around the vendor's text, if anything (e.g. the message layout, a user turn).
    public var adaptation: String?

    public init(origin: String, license: String, verbatim: Bool, adaptation: String? = nil) {
        self.origin = origin
        self.license = license
        self.verbatim = verbatim
        self.adaptation = adaptation
    }

    /// Text written for this kit, under its MIT licence.
    public static let original = ProfileSource(origin: "original", license: "MIT", verbatim: false)
}
