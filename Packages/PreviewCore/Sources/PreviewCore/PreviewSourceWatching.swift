// Narrow request-local event/lifetime seam; native descriptor access stays in PreviewSourceMonitor.
protocol PreviewSourceWatching: AnyObject, Sendable {
    var events: AsyncStream<PreviewSourceMonitor.Event> { get }
    func stop()
}

extension PreviewSourceMonitor: PreviewSourceWatching {}
