import MLXToolKit

/// Builds a `.promptEnhance` `LLMRequest` from a task template and runs it on a caller-supplied
/// `Runner` (which wraps the engine — so the kit stays backbone/engine-agnostic, depending only on
/// `MLXToolKit`). It ALWAYS falls back to the raw prompt — on a missing template, a thrown error,
/// or an empty result — because enhancement is strictly optional and must never block generation.
///
/// **No model package is required.** The kit never loads a model; the host chooses what answers the
/// request. Hosts that already carry a chat-capable text model (e.g. a video pipeline whose text
/// encoder is an instruction-tuned LLM, like LTX's Gemma-3) should drive that model directly via the
/// `generate:` overload instead of registering a separate `.llm` package.
///
/// ⚠️ **Do not let an enhancer integration force a VLM-capable model package into the host.**
/// `mlx-swift-lm`'s model-type registry is process-global and probes VLM factories first; a linked
/// MLXVLM shadows text architectures registered by both (e.g. `gemma3` resolves to the multimodal
/// `Gemma3` instead of `Gemma3TextModel`), breaking hosts that auto-dispatch text models — at link
/// time, even if enhancement is never invoked. (Surfaced by LTX, BRIDGE-LTX-003.)
///
/// Usage — engine-backed (the runner wraps `engine.run`):
/// ```swift
/// let enhancer = PromptEnhancer()
/// let rich = await enhancer.enhance(brief, capability: .textToVideo, task: .textToVideo) { req in
///     (try await engine.run(req) as? LLMResponse)?.text ?? ""
/// }
/// ```
/// Usage — host-provided chat model (no `.llm` package, no `LLMRequest` juggling):
/// ```swift
/// let rich = await enhancer.enhance(brief, capability: .textToVideo, task: .textToVideo) { system, user in
///     try await myChatModel.respond(system: system, user: user)
/// }
/// ```
public struct PromptEnhancer: Sendable {
    public let library: TemplateLibrary
    public var parameters: LLMParameters

    public init(library: TemplateLibrary = TemplateLibrary(),
                parameters: LLMParameters = LLMParameters(temperature: 0.7, maxTokens: 512)) {
        self.library = library
        self.parameters = parameters
    }

    /// "Run an `LLMRequest`, return its text." Wraps whatever drives the engine.
    public typealias Runner = @Sendable (LLMRequest) async throws -> String

    /// Enhance `prompt` for `(capability, task)`. Returns the enhanced text, or `prompt` unchanged
    /// when there is no template, the runner throws, or the result is empty.
    public func enhance(_ prompt: String,
                        capability: Capability,
                        task: EnhanceTask,
                        targetSize: (width: Int, height: Int)? = nil,
                        targetDuration: Double? = nil,
                        run: Runner) async -> String {
        guard let template = library.template(for: capability, task: task) else { return prompt }
        let request = makeRequest(prompt, template: template, targetSize: targetSize,
                                  targetDuration: targetDuration)
        do {
            let text = try await run(request).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? prompt : text
        } catch {
            return prompt
        }
    }

    /// "Run (system, user) on a host-provided chat model, return its text." For hosts that already
    /// carry a chat-capable LLM (a pipeline's own text encoder, a resident assistant model) — no
    /// engine `.llm` package, no `LLMRequest` assembly.
    public typealias Generator = @Sendable (_ system: String, _ user: String) async throws -> String

    /// Enhance `prompt` on a host-provided chat model. Same template selection, hint assembly, and
    /// raw-fallback contract as the `Runner` variant; only the transport differs.
    public func enhance(_ prompt: String,
                        capability: Capability,
                        task: EnhanceTask,
                        targetSize: (width: Int, height: Int)? = nil,
                        targetDuration: Double? = nil,
                        generate: Generator) async -> String {
        guard let template = library.template(for: capability, task: task) else { return prompt }
        let user = makeUserTurn(prompt, targetSize: targetSize, targetDuration: targetDuration)
        do {
            let text = try await generate(template.system, user)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? prompt : text
        } catch {
            return prompt
        }
    }

    /// The exact `.promptEnhance` request the enhancer would run — exposed for inspection/testing.
    /// The size/duration hints ride the user turn (backbone-agnostic) rather than `metaData`, so any
    /// `.llm` package honors them without knowing a package-specific convention. The duration hint
    /// exists for video: prompt detail should scale with clip length (a short prompt for a long clip
    /// leaves the model rushing the action — the LTX-2.3 guide's "long videos need long prompts").
    public func makeRequest(_ prompt: String,
                            template: PromptEnhanceTemplate,
                            targetSize: (width: Int, height: Int)? = nil,
                            targetDuration: Double? = nil) -> LLMRequest {
        LLMRequest(
            messages: [
                ChatMessage(role: .system, content: template.system),
                ChatMessage(role: .user, content: makeUserTurn(prompt, targetSize: targetSize,
                                                               targetDuration: targetDuration)),
            ],
            parameters: parameters,
            mode: .promptEnhance)
    }

    /// The exact user turn (brief + optional size/duration hints) — shared by both transports.
    public func makeUserTurn(_ prompt: String,
                             targetSize: (width: Int, height: Int)? = nil,
                             targetDuration: Double? = nil) -> String {
        var user = prompt
        if let s = targetSize { user += "\n\nTarget resolution: \(s.width)x\(s.height)." }
        if let d = targetDuration, d > 0 {
            user += "\n\nTarget duration: ~\(Int(d.rounded())) seconds of video — describe enough action and detail to fill it."
        }
        return user
    }
}
