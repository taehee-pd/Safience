import Foundation

extension Handoff {
    public enum Failure: String, Equatable, Sendable {
        case reading, writing
        public var message: String {
            switch self {
            case .reading: return "The page could not be read. Try again after it finishes loading."
            case .writing: return "The context file could not be saved. Check available storage and try again."
            }
        }
    }
    public enum ReadOutcome: Sendable {
        case content(PageReading), noReadableContent, protectedPage, failed
    }
    /// How far a handoff is. One value, so that what can't be at once can't
    /// be said at once: there is no file before the page is read, and no
    /// kind told by the model while it is still asked.
    public enum Stage: Equatable, Sendable {
        /// The page is being read and its first file written.
        case reading
        /// The first file is there, its kind told by counting, and Apple
        /// Intelligence's model is asked what the page is.
        case organising(counted: PageKind)
        /// The file is as good as it will get: from here it may be shared (HandoffGuide's button).
        case ready(PageKind)
        /// Nothing to read as text (a picture, a PDF): the words alone go.
        case wordsOnly
        /// Explicitly chosen without claiming the page had no readable text.
        case addressOnly
        case failed(Failure)
        /// Called off before it came to anything.
        case stopped

        /// Whether there is a file to give.
        public var hasFile: Bool {
            switch self {
            case .organising, .ready: return true
            case .reading, .wordsOnly, .addressOnly, .failed, .stopped: return false
            }
        }

        /// Whether the model is still waited for.
        public var isOrganising: Bool {
            if case .organising = self { return true }
            return false
        }

        /// Whether it has come to its end, which nothing changes after.
        public var isSettled: Bool {
            switch self {
            case .ready, .wordsOnly, .addressOnly, .failed, .stopped: return true
            case .reading, .organising: return false
            }
        }

        /// How far one step of the handoff is at this stage. The steps come
        /// one after another, so the one at work has every step before it
        /// done and every step after it waiting; with the file ready, the
        /// step at work is the person's own.
        public func progress(of step: Step) -> Progress {
            let atWork: Step?
            switch self {
            case .reading: atWork = .file
            case .organising: atWork = .organise
            case .ready, .wordsOnly, .addressOnly: atWork = .choose
            // Called off: the sheet is on its way out, and nothing is at work.
            case .stopped, .failed: atWork = nil
            }
            guard let atWork else { return .waiting }
            if step.rawValue < atWork.rawValue { return .done }
            return step == atWork ? .working : .waiting
        }

        /// What the sheet says of the page under the step that organises,
        /// in two lines, as a person would be told it: what is going on or
        /// what the page turned out to be, then what that means for what
        /// they share. The second line of a page still being read says how
        /// long the wait is, which is what a person waiting wants to know.
        ///
        /// Each is one line on the narrowest iPhone, 24 and 32 characters
        /// at the most, since the sheet is as high as it was measured with
        /// the first pair.
        public var headline: String {
            switch self {
            case .reading, .organising, .stopped: return "Reading this page…"
            case .ready(.article): return "This is an article"
            case .ready(.landing): return "This is a landing page"
            case .ready(.app): return "This is a web app"
            case .ready(.product): return "This is a product page"
            case .ready(.thread): return "This is a discussion"
            case .ready(.listing): return "This is a list of links"
            case .ready(.media): return "This is a media page"
            case .ready(.job): return "This is a job posting"
            case .ready(.other): return "This page is ready"
            case .wordsOnly: return "Nothing to read here"
            case .addressOnly: return "Share the page's address"
            case .failed(.reading): return "The page could not be read"
            case .failed(.writing): return "The file could not be saved"
            }
        }

        public var detail: String {
            detail(selected: false)
        }

        /// The second line. With something selected on the page, that is
        /// what the person should hear about: it goes too, and first. And
        /// where a recording's transcript was got from its site (Transcript),
        /// that it goes as well: it is most of what is shared.
        public func detail(selected: Bool, transcribed: Bool = false) -> String {
            switch self {
            case .reading, .organising, .stopped: return "This takes a few seconds."
            case .ready where selected: return "Your selection goes first."
            case .ready where transcribed: return "You'll share its transcript too."
            case .ready(.article), .ready(.other): return "You'll share all of its text."
            case .ready(.landing): return "You'll share its main sections."
            case .ready(.app): return "You'll share what's on the page."
            case .ready(.product): return "You'll share its main details."
            case .ready(.thread): return "You'll share the whole thread."
            case .ready(.listing): return "You'll share one line per item."
            case .ready(.media): return "You'll share its description."
            case .ready(.job): return "You'll share the whole posting."
            case .wordsOnly: return "You'll share the page's address."
            case .addressOnly: return "Its content is not included."
            case .failed: return "Try again or share the address."
            }
        }
    }

    /// The steps of a handoff, in the order they happen, as the sheet shown
    /// meanwhile lists them (HandoffGuide).
    public enum Step: Int, CaseIterable, Sendable {
        /// The page is read and written into a file.
        case file
        /// What the page is is told on the device: by Apple Intelligence's
        /// model where it is there, by the app's own counting where it is not.
        case organise
        /// The person picks the app, and asks their question there.
        case choose
    }

    /// How far a step is.
    public enum Progress: Equatable, Sendable {
        case waiting
        case working
        case done
    }
}
