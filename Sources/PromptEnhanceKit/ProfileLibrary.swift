/// Enhance profiles keyed by the model ids they serve. A host looks up the profile for the model it's about to run;
/// `imageModels()` ships the profiles for the image engine's text-to-image models.
public struct ProfileLibrary: Sendable {
    private var profilesByID: [String: EnhanceProfile] = [:]
    private var idByModel: [String: String] = [:]

    public init(_ profiles: [EnhanceProfile] = []) {
        for profile in profiles { register(profile) }
    }

    /// Every profile, by id.
    public var profiles: [EnhanceProfile] { profilesByID.values.sorted { $0.id < $1.id } }

    public func profile(id: String) -> EnhanceProfile? { profilesByID[id] }

    /// The profile serving `model`, if any.
    public func profile(forModel model: String) -> EnhanceProfile? { idByModel[model].flatMap { profilesByID[$0] } }

    /// Adds `profile`, replacing one with the same id and taking over its model ids.
    public mutating func register(_ profile: EnhanceProfile) {
        if let previous = profilesByID[profile.id] {
            for model in previous.models where idByModel[model] == profile.id { idByModel[model] = nil }
        }
        profilesByID[profile.id] = profile
        for model in profile.models { idByModel[model] = profile.id }
    }

    /// Adds every profile of `other`, replacing ones with the same id (a host's tuned pack over the shipped one).
    public mutating func merge(_ other: ProfileLibrary) {
        for profile in other.profiles { register(profile) }
    }
}

extension TemplateLibrary {
    /// Adds every template of `other`, replacing ones with the same `(capability, task)`: register a whole pack at
    /// once instead of template by template.
    public mutating func merge(_ other: TemplateLibrary) {
        for (key, template) in other.entries { register(template, capability: key.capability, task: key.task) }
    }
}
