import PreviewCore

// Existing thumbnail API names remain compatible while previews share the same timer/reply primitive.
public typealias ThumbnailTimerScheduling = RequestTimerScheduling
public typealias ThumbnailTimerHandle = RequestTimerHandle
public typealias DispatchThumbnailScheduler = DispatchRequestScheduler
public typealias ThumbnailReplyGate<Value: Sendable> = RequestReplyGate<Value>
