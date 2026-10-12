import Foundation
import Synchronization
import PreviewContracts

/// A process resource bound, shared across page views and their replacement schedulers.
/// A running native call retains its lease through cancellation until the call actually returns.
final class ImageDecodeAdmission: Sendable {
    static let processWide = ImageDecodeAdmission()
    enum Event: Equatable, Sendable { case queued, willGrant, acquired, released }
    private enum Kind: Equatable, Sendable { case small, large }

    private struct State {
        var active: [ObjectIdentifier: Ticket] = [:]
        var waiting: [Ticket] = []
    }
    private let state = Mutex(State())
    private let maximumSmallConcurrent: Int
    private let observe: (@Sendable (Event) -> Void)?

    /// The optional value-free observer is an internal seam for deterministic admission tests.
    init(maximumSmallConcurrent: Int = 1, observe: (@Sendable (Event) -> Void)? = nil) {
        self.maximumSmallConcurrent = max(1, maximumSmallConcurrent)
        self.observe = observe
    }

    var runningCount: Int { state.withLock { $0.active.count } }
    var waitingCount: Int { state.withLock { $0.waiting.count } }

    func run<T: Sendable>(sourcePixelCount pixels: Int, ifCancelled cancelled: T,
                         _ work: () async -> T) async -> T {
        guard (1...PreviewImageLimits.maximumSourcePixels).contains(pixels),
              let ticket = await acquire(pixels: pixels) else { return cancelled }
        defer { release(ticket) }
        observe?(.acquired)
        guard !Task.isCancelled else { return cancelled }
        return await work()
    }

    private func acquire(pixels: Int) async -> Ticket? {
        guard !Task.isCancelled else { return nil }
        let kind: Kind = pixels > PreviewImageLimits.serialDecodeThresholdPixels ? .large : .small
        let ticket = Ticket(kind: kind)
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                ticket.park(continuation)
                enqueue(ticket)
            }
        } onCancel: {
            cancel(ticket)
        }
        return granted ? ticket : nil
    }

    private func enqueue(_ ticket: Ticket) {
        let next = state.withLock { state -> (grants: [Ticket], queued: Bool) in
            guard !ticket.isDeclined else { return ([], false) }
            state.waiting.append(ticket)
            let grants = pump(&state)
            return (grants, state.waiting.contains { $0 === ticket })
        }
        if next.queued { observe?(.queued) }
        grant(next.grants)
    }

    private func cancel(_ ticket: Ticket) {
        // Decide first so a cancellation that precedes enqueue cannot leave a declined waiter behind.
        _ = ticket.resolve(false)
        let next = state.withLock { state -> [Ticket] in
            state.waiting.removeAll { $0 === ticket }
            return pump(&state)
        }
        grant(next)
    }

    private func release(_ ticket: Ticket) {
        let next = state.withLock { state -> [Ticket]? in
            guard state.active.removeValue(forKey: ObjectIdentifier(ticket)) != nil else { return nil }
            return pump(&state)
        }
        guard let next else { return }
        observe?(.released)
        grant(next)
    }

    /// FIFO grants are reserved under the state lock and resolved outside it. A large front ticket
    /// waits for every active lease; smaller tickets behind it cannot bypass it and starve it.
    private func pump(_ state: inout State) -> [Ticket] {
        var grants: [Ticket] = []
        while let ticket = state.waiting.first {
            if state.active.values.contains(where: { $0.kind == .large }) { break }
            if ticket.kind == .large {
                guard state.active.isEmpty else { break }
            } else if state.active.count >= maximumSmallConcurrent { break }
            state.waiting.removeFirst()
            state.active[ObjectIdentifier(ticket)] = ticket
            grants.append(ticket)
            if ticket.kind == .large { break }
        }
        return grants
    }

    private func grant(_ tickets: [Ticket]) {
        for ticket in tickets {
            observe?(.willGrant)
            // Cancellation can win between reservation and resolution. Such a ticket never runs
            // work; undo its reservation once and give the capacity to the next waiter.
            if !ticket.resolve(true) { release(ticket) }
        }
    }

    private final class Ticket: Sendable {
        enum Slot { case pending, parked(CheckedContinuation<Bool, Never>), decided(Bool) }
        let kind: Kind
        private let slot = Mutex(Slot.pending)
        init(kind: Kind) { self.kind = kind }

        var isDeclined: Bool {
            slot.withLock { if case .decided(false) = $0 { return true }; return false }
        }

        func park(_ continuation: CheckedContinuation<Bool, Never>) {
            let early = slot.withLock { slot -> Bool? in
                if case .decided(let granted) = slot { return granted }
                slot = .parked(continuation)
                return nil
            }
            if let early { continuation.resume(returning: early) }
        }

        func resolve(_ granted: Bool) -> Bool {
            let result = slot.withLock { slot -> (Bool, CheckedContinuation<Bool, Never>?) in
                switch slot {
                case .pending: slot = .decided(granted); return (true, nil)
                case .parked(let continuation): slot = .decided(granted); return (true, continuation)
                case .decided: return (false, nil)
                }
            }
            result.1?.resume(returning: granted)
            return result.0
        }
    }
}
