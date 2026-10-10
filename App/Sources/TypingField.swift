import SwiftUI
import UIKit

/// A text field for the address and the palette that tells what is typed as
/// it shows it, the letters still being composed included, and gives them
/// all to Return.
///
/// SwiftUI's TextField leaves marked text, a composition not yet committed,
/// out of its binding until the next key commits it. The Korean keyboard
/// keeps the last letter typed marked, Latin letters too, so the palette
/// offered "Open github.co" for github.com and Return opened github.co; a
/// search in Korean lost its last syllable the same way.
struct TypingField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var fontSize: CGFloat = 13
    @Binding var focused: Bool
    /// All of it selected as it takes the keys, so typing replaces it.
    var selectsAll = false
    let submit: (String) -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = Palette.UI.ink
        field.keyboardType = .webSearch
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .go
        field.text = text
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Only text set from outside (an address to edit, a clear), never
        // what the field itself just said, and never mid-composition: that
        // would end it.
        if field.markedTextRange == nil, text != coordinator.said, field.text != text {
            field.text = text
            coordinator.said = text
        }
        // A turn later, as SwiftUI asks, and only if it still asks then.
        if focused != field.isFirstResponder {
            DispatchQueue.main.async {
                let wanted = coordinator.parent.focused
                if wanted, !field.isFirstResponder {
                    _ = field.becomeFirstResponder()
                } else if !wanted, field.isFirstResponder {
                    _ = field.resignFirstResponder()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TypingField
        /// The text the field last passed on.
        var said: String

        init(parent: TypingField) {
            self.parent = parent
            said = parent.text
        }

        @objc func changed(_ field: UITextField) {
            said = field.text ?? ""
            parent.text = said
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            // What is still being composed is part of what Return sends.
            field.unmarkText()
            let typed = field.text ?? ""
            said = typed
            parent.text = typed
            parent.submit(typed)
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.focused { parent.focused = true }
            // The field's own selection: sent to no one in particular, select
            // all reached the page when it still had the keys, and the page
            // took them back.
            if parent.selectsAll {
                DispatchQueue.main.async { if field.isFirstResponder { field.selectAll(nil) } }
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.focused { parent.focused = false }
        }
    }
}
