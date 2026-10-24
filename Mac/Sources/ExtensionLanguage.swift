import Foundation
import NaturalLanguage

/// Local detection for extension-supplied text and authorized tab text. Samples
/// are capped before recognition; no text is stored or sent to a service.
enum ExtensionLanguage {
    nonisolated static let maximumScalars = 16_384
    nonisolated private static let segmentScalars = 512

    struct Language: Sendable {
        let language: String
        let percentage: Int
    }

    struct Detection: Sendable {
        let isReliable: Bool
        let languages: [Language]

        var json: [String: Any] {
            ["isReliable": isReliable, "languages": languages.map { ["language": $0.language, "percentage": $0.percentage] as [String: Any] }]
        }

        var locale: Locale? {
            guard let first = languages.first, first.percentage >= 50 else { return nil }
            return Locale(identifier: first.language)
        }
    }

    nonisolated static func detect(_ text: String) -> Detection {
        let sample = String(String.UnicodeScalarView(text.unicodeScalars.prefix(maximumScalars)))
        var weights: [String: Double] = [:]
        var total = 0.0
        var confident = 0.0
        let recognizer = NLLanguageRecognizer()
        for paragraph in sample.split(whereSeparator: \.isNewline) {
            let scalars = Array(paragraph.unicodeScalars)
            for offset in stride(from: 0, to: scalars.count, by: segmentScalars) {
                let segment = String(String.UnicodeScalarView(scalars[offset..<min(offset + segmentScalars, scalars.count)]))
                let letters = segment.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
                guard letters > 0 else { continue }
                recognizer.reset()
                recognizer.processString(segment)
                guard let language = recognizer.dominantLanguage else { continue }
                let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
                let code = language == .simplifiedChinese ? "zh-CN" : language == .traditionalChinese ? "zh-TW" : language.rawValue
                weights[code, default: 0] += Double(letters)
                total += Double(letters)
                confident += Double(letters) * confidence
            }
        }
        guard total > 0 else { return Detection(isReliable: false, languages: []) }
        let ranked = weights.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(3)
        let languages = ranked.map { Language(language: $0.key, percentage: Int(($0.value / total * 100).rounded())) }
        let reliable = total >= 20 && confident / total >= 0.8
        return Detection(isReliable: reliable, languages: languages)
    }

    /// The caller owns page access and supplies its HandsOff-gated sampler.
    /// Recheck after sampling so navigation or revoked access discards the result.
    @MainActor
    static func webpage(isAllowed: @escaping @MainActor () -> Bool,
                        sample: @MainActor () async throws -> String?) async throws -> Detection? {
        guard isAllowed() else { return nil }
        let text = try await sample()
        guard isAllowed(), let text else { return nil }
        return detect(text)
    }

    // Walk rendered text only. Skip form values, editors and hidden subtrees.
    // Both the visited-node count and the returned UTF-16 length are bounded.
    static let sampleText = #"""
    if (location.href !== expectedURL || protectedHosts.some(host => location.hostname === host || location.hostname.endsWith("." + host))) return null;
    const root = document.body;
    if (!root) return "";
    const skip = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "INPUT", "TEXTAREA", "SELECT"]);
    let visited = 0, text = "", node = root;
    while (node && visited++ < 2000 && text.length < limit) {
      let descend = true;
      if (node.nodeType === Node.TEXT_NODE) {
        text += (node.nodeValue || "").slice(0, limit - text.length) + "\n";
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        const style = getComputedStyle(node);
        descend = !(skip.has(node.tagName) || node.isContentEditable || node.hidden || node.getAttribute("aria-hidden") === "true" ||
          style.display === "none" || style.visibility === "hidden" || style.contentVisibility === "hidden");
      }
      if (descend && node.firstChild) { node = node.firstChild; continue; }
      while (node && node !== root && !node.nextSibling) node = node.parentNode;
      node = node && node !== root ? node.nextSibling : null;
    }
    return text.slice(0, limit);
    """#
}
