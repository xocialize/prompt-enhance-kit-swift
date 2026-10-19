import Foundation
import MLXToolKit

/// How hard to try.
public enum EnhanceMode: String, Sendable, Equatable, CaseIterable {
    /// Follow the profile's policy: always for `required`, a brief that isn't already detailed for `recommended`,
    /// never for `optional`.
    case auto
    /// Enhance whenever the profile has an instruction for the task (a structured brief still passes through).
    case always
}

/// What happened to a prompt, with everything a host needs for provenance.
public struct EnhanceResult: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        /// Rewritten; `prompt` is the enhancer's.
        case enhanced
        /// Already detailed or structured: sent as typed.
        case passedThrough
        /// `auto` and the profile's policy is `optional`: sent as typed.
        case notRecommended
        /// The profile has no instruction for the task.
        case noInstruction
        /// The task needs to see the input images, and the kit has no image transport yet.
        case needsVision
        /// The backbone failed, or its answer couldn't be read.
        case failed
        /// The backbone didn't answer within the timeout.
        case timedOut
        /// The backbone answered with nothing.
        case empty
    }

    /// What to send to the image model: the rewrite, or the brief as typed.
    public var prompt: String
    public var original: String
    public var outcome: Outcome
    public var profileID: String
    public var profileVersion: Int
    /// Whether the Chinese instruction variant was used.
    public var usedChineseInstruction: Bool
    /// Other top-level scalars of a JSON answer (e.g. `wh_ratio`), as strings.
    public var fields: [String: String]
    /// Why it failed, for logs.
    public var failure: String?

    public var applied: Bool { outcome == .enhanced }

    public init(prompt: String, original: String, outcome: Outcome, profileID: String, profileVersion: Int,
                usedChineseInstruction: Bool = false, fields: [String: String] = [:], failure: String? = nil) {
        self.prompt = prompt; self.original = original; self.outcome = outcome; self.profileID = profileID
        self.profileVersion = profileVersion; self.usedChineseInstruction = usedChineseInstruction
        self.fields = fields; self.failure = failure
    }
}

extension PromptEnhancer {
    /// "Run (system, user) on a host-provided chat model." The system turn is optional: a dedicated enhancer may bring
    /// its own instruction.
    public typealias ProfileGenerator = @Sendable (_ system: String?, _ user: String) async throws -> String

    /// Enhance `prompt` for a model, with its profile. Unlike the template overloads it reports what happened, and
    /// it **rethrows cancellation** rather than answering with the raw prompt, so a cancelled job stops instead of
    /// generating from an unenhanced prompt. Every other failure (an error, a timeout, an empty or unreadable answer)
    /// returns the brief as typed, with the outcome saying why: enhancement never blocks generation.
    ///
    /// `timeout` bounds the backbone's answer. The run is cancelled when it expires; a backbone that ignores
    /// cancellation still delays the return until it finishes.
    public func enhance(_ prompt: String, profile: EnhanceProfile, task: EnhanceTask, mode: EnhanceMode = .auto,
                        targetSize: (width: Int, height: Int)? = nil, timeout: Duration? = nil,
                        run: @escaping Runner) async throws -> EnhanceResult {
        try await runProfile(prompt, profile: profile, task: task, mode: mode, targetSize: targetSize, timeout: timeout) {
            request in try await run(request)
        }
    }

    /// The same, on a host-provided chat model. Structured output can't be constrained on this transport; the
    /// answer is still parsed as JSON for a `.json` profile.
    public func enhance(_ prompt: String, profile: EnhanceProfile, task: EnhanceTask, mode: EnhanceMode = .auto,
                        targetSize: (width: Int, height: Int)? = nil, timeout: Duration? = nil,
                        generate: @escaping ProfileGenerator) async throws -> EnhanceResult {
        try await runProfile(prompt, profile: profile, task: task, mode: mode, targetSize: targetSize, timeout: timeout) {
            request in
            let system = request.messages.first { $0.role == .system }?.content
            let user = request.messages.last { $0.role == .user }?.content ?? ""
            return try await generate(system, user)
        }
    }

    private func runProfile(_ prompt: String, profile: EnhanceProfile, task: EnhanceTask, mode: EnhanceMode,
                         targetSize: (width: Int, height: Int)?, timeout: Duration?,
                         call: @escaping @Sendable (LLMRequest) async throws -> String) async throws -> EnhanceResult {
        func result(_ outcome: EnhanceResult.Outcome, _ text: String? = nil, chinese: Bool = false,
                    fields: [String: String] = [:], failure: String? = nil) -> EnhanceResult {
            EnhanceResult(prompt: text ?? prompt, original: prompt, outcome: outcome, profileID: profile.id,
                          profileVersion: profile.version, usedChineseInstruction: chinese, fields: fields,
                          failure: failure)
        }
        if let skip = Self.decision(prompt, profile: profile, task: task, mode: mode) { return result(skip) }
        guard let (request, instruction, chinese) = makeRequest(prompt, profile: profile, task: task,
                                                                targetSize: targetSize) else {
            return result(.noInstruction)
        }
        let answer: String?
        do {
            answer = try await Self.withTimeout(timeout) { try await call(request) }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return result(.failed, chinese: chinese, failure: "\(error)")
        }
        try Task.checkCancellation()
        guard let answer else { return result(.timedOut, chinese: chinese) }
        do {
            guard let (text, fields) = try Self.read(answer, output: profile.output) else {
                return result(.empty, chinese: chinese)
            }
            return result(.enhanced, Self.append(instruction.suffix, to: text, chinese: chinese), chinese: chinese,
                          fields: fields)
        } catch {
            return result(.failed, chinese: chinese, failure: "\(error)")
        }
    }

    /// The request a profile makes for `prompt`, the instruction it used, and whether that was the Chinese variant.
    /// `nil` when the profile has no instruction for the task. Exposed for inspection and tests.
    public func makeRequest(_ prompt: String, profile: EnhanceProfile, task: EnhanceTask,
                            targetSize: (width: Int, height: Int)? = nil)
        -> (request: LLMRequest, instruction: EnhanceInstruction, chinese: Bool)? {
        guard let set = profile.instructions[task] else { return nil }
        let chinese = set.chinese != nil && Self.containsCJK(prompt)
        let instruction = chinese ? set.chinese! : set.standard
        let brief = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var user = instruction.user.replacingOccurrences(of: "{prompt}", with: brief)
        if let size = targetSize { user += "\n\nTarget resolution: \(size.width)x\(size.height)." }
        var messages: [ChatMessage] = []
        if let system = instruction.system {
            messages.append(ChatMessage(role: .system, content: system.replacingOccurrences(of: "{prompt}", with: brief)))
        }
        messages.append(ChatMessage(role: .user, content: user))
        let format: ResponseFormat? = switch profile.output {
        case .text: nil
        case .json(let schema, _): schema.map { .jsonSchema($0) } ?? .json(container: .object)
        }
        let request = LLMRequest(messages: messages, parameters: profile.sampling.applied(to: parameters),
                                 mode: .promptEnhance, responseFormat: format)
        return (request, instruction, chinese)
    }

    // MARK: - Decisions

    /// Why a prompt goes through as typed without calling the backbone, or `nil` to enhance it.
    static func decision(_ prompt: String, profile: EnhanceProfile, task: EnhanceTask,
                         mode: EnhanceMode) -> EnhanceResult.Outcome? {
        guard profile.instructions[task] != nil else { return .noInstruction }
        if task.needsVision { return .needsVision }
        if profile.passThrough.structured, isStructured(prompt) { return .passedThrough }
        guard mode == .auto else { return nil }
        switch profile.policy {
        case .required: return nil
        case .optional: return .notRecommended
        case .recommended:
            if let words = profile.passThrough.detailedAtWords, wordCount(prompt) >= words { return .passedThrough }
            return nil
        }
    }

    /// Whitespace-separated words, with CJK ideographs counted two to a word (they carry no spaces).
    static func wordCount(_ text: String) -> Int {
        let ideographs = text.unicodeScalars.filter(isIdeograph).count
        let words = text.split(whereSeparator: { $0.isWhitespace }).filter { word in
            !word.unicodeScalars.allSatisfy(isIdeograph)
        }.count
        return words + (ideographs + 1) / 2
    }

    /// The test Qwen-Image's rewriter uses to pick its Chinese instruction: any CJK unified ideograph.
    static func containsCJK(_ text: String) -> Bool { text.unicodeScalars.contains(where: isIdeograph) }

    private static func isIdeograph(_ scalar: Unicode.Scalar) -> Bool { (0x4E00...0x9FFF).contains(scalar.value) }

    /// A brief that is already a JSON object or array.
    static func isStructured(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

    // MARK: - Reading the answer

    struct UnreadableAnswer: Error, CustomStringConvertible {
        let description: String
    }

    /// The prompt and any extra fields from the backbone's answer, or `nil` when it said nothing.
    static func read(_ answer: String, output: EnhanceOutput) throws -> (String, [String: String])? {
        guard let answer = stripReasoning(answer) else { return nil }
        var text = stripFences(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        switch output {
        case .text(let singleLine):
            text = stripWrappingQuotes(text)
            if singleLine {
                text = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
            return text.isEmpty ? nil : (text, [:])
        case .json(_, let promptField):
            guard !text.isEmpty else { return nil }
            guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else {
                throw UnreadableAnswer(description: "The answer isn't JSON: \(text.prefix(120))")
            }
            var fields: [String: String] = [:]
            if let object = value as? [String: Any] {
                for (key, scalar) in object where key != promptField {
                    if let string = scalar as? String { fields[key] = string }
                    else if let number = scalar as? NSNumber { fields[key] = number.stringValue }
                }
            }
            guard let promptField else {
                let compact = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes,
                                                                                          .fragmentsAllowed])
                return (String(decoding: compact, as: UTF8.self), fields)
            }
            guard let prompt = (value as? [String: Any])?[promptField] as? String else {
                throw UnreadableAnswer(description: "The answer has no string \"\(promptField)\".")
            }
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (trimmed, fields)
        }
    }

    /// The answer after a reasoning model's `<think>…</think>` block, or `nil` when the block never closed (the token
    /// budget ran out mid-thought, so there's no answer). A template that pre-fills `<think>` leaves only the closing
    /// tag in the text; anything before the last `</think>` is reasoning either way.
    static func stripReasoning(_ answer: String) -> String? {
        if let close = answer.range(of: "</think>", options: .backwards) { return String(answer[close.upperBound...]) }
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<think>") { return nil }
        return answer
    }

    /// A ```-fenced answer's contents (some backbones fence even when told not to).
    static func stripFences(_ text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 else { return text }
        var inner = text.dropFirst(3).dropLast(3)
        if let newline = inner.firstIndex(of: "\n"), !inner[..<newline].contains(" ") {
            inner = inner[inner.index(after: newline)...]           // drop a language tag such as ```json
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An answer wrapped in one pair of quotes, unwrapped.
    static func stripWrappingQuotes(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("「", "」")]
        for (open, close) in pairs where text.count > 2 && text.first == open && text.last == close {
            let inner = text.dropFirst().dropLast()
            if !inner.contains(open) && !inner.contains(close) { return String(inner) }
        }
        return text
    }

    static func append(_ suffix: String?, to text: String, chinese: Bool) -> String {
        guard let suffix, !suffix.isEmpty else { return text }
        return chinese ? text + suffix : text + " " + suffix
    }

    // MARK: - Timeout

    /// `operation`'s result, or `nil` when `timeout` passes first. Cancelling the caller cancels both.
    static func withTimeout<T: Sendable>(_ timeout: Duration?,
                                         _ operation: @escaping @Sendable () async throws -> T) async throws -> T? {
        guard let timeout else { return try await operation() }
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }
}
