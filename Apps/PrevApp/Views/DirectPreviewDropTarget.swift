import AppKit
import SwiftUI

enum DirectPreviewDropFeedback: Equatable {
    case idle, targeted, rejected
}

/// A narrow native target reads a dropped NSURL synchronously. It never requests
/// file contents, promised files, or asynchronous item-provider representations.
struct DirectPreviewDropTarget: NSViewRepresentable {
    @Binding var feedback: DirectPreviewDropFeedback
    /// Called once for each drop that is refused, not for a hover, so the page can announce it.
    let rejected: @MainActor () -> Void
    let open: @MainActor (URL) -> Void

    func makeNSView(context: Context) -> DirectPreviewDropView {
        let view = DirectPreviewDropView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DirectPreviewDropView, context: Context) {
        view.onFeedback = { feedback = $0 }
        view.onRejectedDrop = rejected
        view.onOpen = open
    }

    static func dismantleNSView(_ view: DirectPreviewDropView, coordinator: ()) {
        view.onFeedback = nil
        view.onRejectedDrop = nil
        view.onOpen = nil
    }
}

@MainActor
final class DirectPreviewDropView: NSView {
    var onFeedback: (@MainActor (DirectPreviewDropFeedback) -> Void)?
    var onRejectedDrop: (@MainActor () -> Void)?
    var onOpen: (@MainActor (URL) -> Void)?
    private var rejectedDrop = false

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .URL])
        // SwiftUI supplies the localized label and Open provides keyboard access.
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        rejectedDrop = false
        return updateFeedback(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateFeedback(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFeedback?(.idle)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        if !rejectedDrop { onFeedback?(.idle) }
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        acceptsMetadata(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard acceptsMetadata(sender),
              let url = DirectPreviewFileDrop.fileURL(from: sender.draggingPasteboard),
              let onOpen else {
            rejectedDrop = true
            onFeedback?(.rejected)
            onRejectedDrop?()
            return false
        }
        onFeedback?(.idle)
        // No suspended URL load can arrive later and overwrite a subsequent Open.
        onOpen(url)
        return true
    }

    private func acceptsMetadata(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingSourceOperationMask.contains(.copy)
            && DirectPreviewFileDrop.isCandidate(sender.draggingPasteboard)
    }

    private func updateFeedback(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let accepts = acceptsMetadata(sender)
        onFeedback?(accepts ? .targeted : .rejected)
        return accepts ? .copy : []
    }
}
