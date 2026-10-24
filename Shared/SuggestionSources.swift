import Foundation
import PadCore

/// What an address field's rows hear from outside the field as typing goes
/// on, both apps': the search engine's suggestions (ask), the space's
/// history (recall), and what Apple Intelligence's on-device model makes of
/// the words (think). Each is asked again as the text changes, and an answer
/// to text the field no longer holds is dropped. The iPhone and iPad's
/// Suggestions and the Mac's each have one, and say what they need of it as
/// they ask: their settings, and whether the model may be asked at all.
@MainActor
final class SuggestionSources {
    /// The engine's words, and the text they answered.
    private(set) var answer: (query: String, words: [String]) = ("", [])
    /// The engine that gave them: shown only while Settings still allows that one.
    private(set) var answerProvider: String?
    /// The space's history for the text, and the text and the space it answered.
    private(set) var remembered: (query: String, space: UUID?, pages: [HistoryPage]) = ("", nil, [])
    /// What the model found the words mean, its searches, and the text it answered.
    private(set) var thought: (query: String, meant: [Suggestion], searches: [Suggestion]) = ("", [], [])
    /// The engine was asked for this text: the model's searches stay out.
    private(set) var asksEngine = false
    private var asking: Task<Void, Never>?
    private var recalling: Task<Void, Never>?
    private var thinking: Task<Void, Never>?
    /// Apple Intelligence's model, where the system has it. Made when an
    /// address is first typed, not with the window: nothing of the model's
    /// framework runs as the app starts.
    private lazy var mind = IntelligenceStatus.model()
    /// Whether the model can answer, asked once for a turn at the field.
    private var mindReady: Bool?

    /// What the field holds now: an answer to anything else is dropped.
    private let query: @MainActor () -> String
    /// The rows the field shows now: the model's picks leave out what they offer already.
    private let rows: @MainActor () -> [Suggestion]
    /// The space the field's rows are made for, if they are made yet.
    private let space: @MainActor () -> UUID?
    /// An answer has come: the rows are to be made again.
    private let changed: @MainActor () -> Void

    init(query: @escaping @MainActor () -> String, rows: @escaping @MainActor () -> [Suggestion],
         space: @escaping @MainActor () -> UUID?, changed: @escaping @MainActor () -> Void) {
        self.query = query
        self.rows = rows
        self.space = space
        self.changed = changed
    }

    /// Nothing is asked of the engine, history or the model, and nothing they said is kept.
    func quiet() {
        asking?.cancel()
        recalling?.cancel()
        thinking?.cancel()
        answer = ("", [])
        remembered = ("", nil, [])
        thought = ("", [], [])
    }

    /// Typing is over, sent or not: the next turn at the field asks the model again whether it is ready.
    func end() {
        asking?.cancel()
        asking = nil
        recalling?.cancel()
        recalling = nil
        thinking?.cancel()
        thinking = nil
        mindReady = nil
        answer = ("", [])
        remembered = ("", nil, [])
        thought = ("", [], [])
    }

    /// The approved provider's suggestions. Partial private names may be
    /// sent before they become complete addresses, as Settings discloses.
    /// Never for an address (suggestionsURL), and dropped when Settings
    /// takes the approval back while they are on their way.
    func ask(_ text: String, preferences: Preferences) {
        asking?.cancel()
        guard let url = Autocomplete.suggestionsURL(for: text, preferences: preferences) else {
            asksEngine = false
            answer = ("", [])
            return
        }
        asksEngine = true
        let engine = preferences.engine
        asking = Task { [weak self] in
            // A moment first, so a word typed quickly asks once, not once a letter.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.query() == text,
                  Session.shared.preferences.allowsRemoteSuggestions(for: engine) else { return }
            guard let reply = try? await SuggestionSources.session.data(from: url),
                  (reply.1 as? HTTPURLResponse)?.statusCode == 200,
                  !Task.isCancelled, self.query() == text,
                  Session.shared.preferences.allowsRemoteSuggestions(for: engine)
            else { return }
            answerProvider = engine
            answer = (text, Autocomplete.parse(reply.0))
            changed()
        }
    }

    /// The space's history for `text` (HistoryRecorder.search), as it comes.
    /// The store looks inside words and in descriptions, which the letters
    /// alone don't: its rows are its own (Autocomplete.history).
    func recall(_ text: String, in space: UUID) {
        recalling?.cancel()
        recalling = Task { [weak self] in
            let pages = await HistoryRecorder.shared.search(space: space, text: text, limit: 12)
            guard !Task.isCancelled, let self, self.query() == text, self.space() == space else { return }
            remembered = (text, space, pages)
            changed()
        }
    }

    /// Whether the model is left alone for now: in Low Power Mode, and
    /// while the device says it is hot. Running a language model is the
    /// most the app ever asks of the device, and the rows it adds are an
    /// extra; the letters still find everything they found before.
    private static var sparesTheModel: Bool {
        let process = ProcessInfo.processInfo
        return process.isLowPowerModeEnabled || process.thermalState == .serious || process.thermalState == .critical
    }

    /// What Apple Intelligence's model makes of `text`, once typing pauses,
    /// where `allowed` (Settings has it on, and the device has it) and the
    /// model is ready. Not for fewer than three letters, nor an address
    /// (intentQuestion).
    func think(_ text: String, about offered: Autocomplete.Index, allowed: Bool) {
        thinking?.cancel()
        guard allowed, Autocomplete.asksModel(text), Self.sparesTheModel == false, let mind else {
            thought = ("", [], [])
            return
        }
        let ready = mindReady ?? mind.ready
        // Kept for the turn once it is known: until then it is only a guess.
        if mind.isKnown { mindReady = ready }
        guard ready else {
            thought = ("", [], [])
            return
        }
        // The model is loaded here, the first time words are typed that it
        // may be asked about, and not as the field is tapped: most turns at
        // the field are an address or a search sent at once, and loading
        // the model each time was work, and warmth, for nothing.
        mind.prewarm()
        let wantsSearches = !asksEngine
        let space = self.space()
        thinking = Task { [weak self] in
            // Longer than the engine's pause: the model's answer costs the
            // device a moment of its own, so it waits for the typing to stop.
            // The question, a list of every candidate, is made after the
            // pause as well: one a pause, not one a letter.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            // The space's history it reads as well: what any of the words
            // is in, and the pages most gone to, for what the words mean.
            let visited = if let space { await HistoryRecorder.shared.recall(space: space, text: text) } else { [HistoryPage]() }
            guard !Task.isCancelled,
                  let question = Autocomplete.intentQuestion(query: text, candidates: offered.candidates,
                                                             history: visited.map(Autocomplete.candidate(for:))),
                  let reply = await mind.answer(question, searches: wantsSearches),
                  !Task.isCancelled, let self, self.query() == text
            else { return }
            // What it picked is only what the words might mean: it picks
            // something for a web search too. Its searches show now; a pick
            // shows once the model, asked about that thing alone, says it
            // fits. Not one the rows offer already, by letters or from history.
            let searches = Autocomplete.intentSearches(reply, to: question)
            let picked = Autocomplete.intentPicks(reply, to: question, shown: self.rows().filter { !$0.byMeaning })
            thought = (text, [], searches)
            changed()
            guard !picked.isEmpty else { return }
            // All asked at once, since they wait on each other little; the
            // rows stay in the order the model picked them in.
            await withTaskGroup(of: (Int, Autocomplete.IntentGrade?).self) { group in
                for (place, candidate) in picked.enumerated() {
                    let about = Autocomplete.gradeQuestion(query: question.query, about: candidate)
                    group.addTask { (place, await mind.grade(about)) }
                }
                var fits: Set<Int> = []
                for await (place, grade) in group {
                    guard !Task.isCancelled, self.query() == text else {
                        group.cancelAll()
                        return
                    }
                    guard grade?.keeps == true else { continue }
                    fits.insert(place)
                    let meant = picked.indices.filter(fits.contains).map {
                        Autocomplete.meantRow(for: picked[$0], query: question.query)
                    }
                    self.thought = (text, meant, searches)
                    self.changed()
                }
            }
        }
    }

    /// Cookies and cache are disabled. The provider still receives the
    /// typed text and connection metadata, including the IP address.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()
}
