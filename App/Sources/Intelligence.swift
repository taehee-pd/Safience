import FoundationModels
import PadCore

/// Apple Intelligence's on-device model, asked what the words typed in the
/// address bar mean: which of the space's tabs, pinned tabs and bookmarks,
/// or which of the browser's commands, and what searches they are on the
/// way to (Autocomplete.intentQuestion). The model is on the device, and
/// nothing it reads leaves it.
///
/// Only on iOS and iPadOS 26 and later, on a device with Apple Intelligence
/// turned on; FoundationModels is linked weakly (project.yml), so earlier
/// versions start without it and the address bar matches letters alone.
@MainActor
protocol Intelligence: AnyObject {
    /// It can answer now: Apple Intelligence on, its model downloaded.
    var ready: Bool { get }
    /// Loads the model as typing starts, so the first answer doesn't wait for it.
    func prewarm()
    /// Nil when it couldn't answer: a refusal, a language it doesn't have,
    /// typing that moved on.
    func answer(_ question: Autocomplete.IntentQuestion) async -> Autocomplete.IntentAnswer?
}

/// What Settings says about Apple Intelligence on this device.
enum IntelligenceStatus {
    case ready
    /// Apple Intelligence is off in the Settings app.
    case turnedOff
    /// The model is still downloading.
    case preparing
    /// Before iOS 26, or a device without Apple Intelligence.
    case unsupported

    @MainActor static var current: IntelligenceStatus {
        guard #available(iOS 26.0, *) else { return .unsupported }
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return .ready }
        if case .unavailable(.appleIntelligenceNotEnabled) = availability { return .turnedOff }
        if case .unavailable(.modelNotReady) = availability { return .preparing }
        return .unsupported
    }

    /// The model, where this version of the system has it.
    @MainActor static func model() -> Intelligence? {
        guard #available(iOS 26.0, *) else { return nil }
        return OnDeviceIntelligence()
    }
}

@available(iOS 26.0, *)
@MainActor
private final class OnDeviceIntelligence: Intelligence {
    private let model = SystemLanguageModel.default
    private var warm: LanguageModelSession?

    var ready: Bool {
        model.isAvailable
    }

    func prewarm() {
        guard ready, warm == nil else { return }
        let session = makeSession()
        session.prewarm()
        warm = session
    }

    func answer(_ question: Autocomplete.IntentQuestion) async -> Autocomplete.IntentAnswer? {
        guard ready else { return nil }
        // A session for each question: a session keeps what it was asked
        // before, and a burst of typing would fill its context.
        let session = warm ?? makeSession()
        warm = nil
        do {
            let reply = try await session.respond(to: question.prompt, generating: AddressIntent.self,
                                                  options: GenerationOptions(sampling: .greedy))
            return Autocomplete.IntentAnswer(picks: reply.content.items, searches: reply.content.searches)
        } catch {
            return nil
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Autocomplete.intentInstructions)
    }
}

/// The model's answer, in the shape the framework holds it to.
@available(iOS 26.0, *)
@Generable
struct AddressIntent {
    @Guide(description: "The numbers of the listed items the person most likely means, best first; empty when none fits",
           .maximumCount(3))
    var items: [Int]

    @Guide(description: "Web searches that finish what the person is typing, in the language they type in",
           .maximumCount(3))
    var searches: [String]
}
