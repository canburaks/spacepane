import AppKit
import SwiftUI

/// The File Types search box: a native `NSSearchField`, so it has the magnifier, the clear button, Escape to clear
/// and the search role VoiceOver expects. It reports every change of the text; the page filters. `focusRequest`
/// moves focus into the field each time it changes, which is how the page's view-scoped ⌘F reaches it.
struct FileTypeSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.lineBreakMode = .byTruncatingTail
        updateNSView(field, context: context)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
        field.setAccessibilityLabel(prompt)
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }

    static func dismantleNSView(_ field: NSSearchField, coordinator: Coordinator) {
        field.delegate = nil
        field.target = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var focusRequest = 0

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            publish(field.stringValue)
        }

        /// The clear button and Escape arrive here rather than as a text change.
        @objc func searchChanged(_ field: NSSearchField) { publish(field.stringValue) }

        private func publish(_ value: String) {
            if text.wrappedValue != value { text.wrappedValue = value }
        }
    }
}
