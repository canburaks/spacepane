import AppKit
import PreviewContracts

/// Finder and companion hosts embed the same native accessible controls.
@MainActor
public final class NativeMIDIPreviewView: NSView, PreviewAnnouncing {
    private let playButton = NSButton(title: "", target: nil, action: nil)
    private let positionSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let timeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let controls = NSStackView()
    private let content = NSStackView()
    private let player = NativeMIDIPlayback()
    private var duration: Double = 0
    /// What the view says aloud: a playback failure, which otherwise changes the status line silently. The preview
    /// hands its own announcer in (`PreviewAnnouncing`); a view used alone keeps this one.
    var announcer: PreviewAnnouncer? = PreviewAnnouncer()
    /// The preview's palette once the host applies it; until then the view draws in the Standard scheme.
    private var palette: NativeTextPalette?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playButton.bezelStyle = .rounded
        playButton.target = self
        playButton.action = #selector(togglePlayback)
        playButton.title = PreviewStrings.text(.midiPlay)
        playButton.toolTip = playButton.title
        playButton.isEnabled = false
        playButton.setAccessibilityHelp(PreviewStrings.text(.midiPlaybackHelp))
        positionSlider.target = self
        positionSlider.action = #selector(seek)
        positionSlider.isContinuous = true
        positionSlider.isEnabled = false
        positionSlider.userInterfaceLayoutDirection = .leftToRight
        positionSlider.setAccessibilityLabel(PreviewStrings.text(.midiPosition))
        positionSlider.toolTip = PreviewStrings.text(.midiPosition)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        timeLabel.userInterfaceLayoutDirection = .leftToRight
        timeLabel.setAccessibilityLabel(PreviewStrings.text(.midiDuration))
        refreshInk()
        statusLabel.stringValue = PreviewStrings.text(.midiNoAutoplay)
        statusLabel.isSelectable = true
        controls.setViews([playButton, positionSlider, timeLabel], in: .leading)
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10
        content.setViews([controls, statusLabel], in: .leading)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            controls.widthAnchor.constraint(equalTo: content.widthAnchor),
            positionSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
        player.onChange = { [weak self] seconds, playing in self?.update(seconds: seconds, playing: playing) }
        player.onFailure = { [weak self] failure in
            guard let self else { return }
            let message = PreviewStrings.text(failure == .soundBankUnavailable ? .midiSoundBankUnavailable : .midiPlaybackUnavailable)
            statusLabel.stringValue = message
            if statusLabel.maximumNumberOfLines == 1 {
                statusLabel.toolTip = message.isEmpty ? nil : message
            }
            announcer?.announce(message, from: self)
        }
        updateChromeForWidth(frameRect.width)
    }
    public required init?(coder: NSCoder) { nil }
    isolated deinit { player.clear() }
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
    public override func layout() {
        updateChromeForWidth(bounds.width)
        super.layout()
    }
    private func updateChromeForWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        let isCompact = width < PreviewChrome.compactWidth - PreviewChrome.compactHysteresis
        playButton.controlSize = isCompact ? .small : .regular
        positionSlider.controlSize = isCompact ? .small : .regular
        controls.spacing = isCompact ? 6 : 10
        content.spacing = isCompact ? 4 : 8
        statusLabel.maximumNumberOfLines = isCompact ? 1 : 0
        statusLabel.lineBreakMode = isCompact ? .byTruncatingTail : .byWordWrapping
        statusLabel.toolTip = isCompact && !statusLabel.stringValue.isEmpty ? statusLabel.stringValue : nil
    }
    public func show(_ presentation: MIDIPresentation) {
        duration = presentation.durationSeconds
        positionSlider.maxValue = max(0.001, duration)
        positionSlider.isEnabled = duration > 0
        playButton.isEnabled = duration > 0
        statusLabel.stringValue = PreviewStrings.text(.midiNoAutoplay)
        if statusLabel.maximumNumberOfLines == 1 {
            statusLabel.toolTip = statusLabel.stringValue.isEmpty ? nil : statusLabel.stringValue
        }
        player.load(presentation)
        update(seconds: 0, playing: false)
    }
    public func clear() {
        player.clear()
        duration = 0
        playButton.isEnabled = false
        positionSlider.isEnabled = false
        positionSlider.maxValue = 1
        update(seconds: 0, playing: false)
    }
    public func stopPlayback() { player.suspend() }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { player.suspend() }
    }

    /// Draws the status line in the preview's own quiet ink (decision 027, Q-34) instead of a system ink that ignores the
    /// chosen color scheme. Where a scheme's body ink leaves no room for a lighter muted ink, the size is the second cue.
    func apply(palette: NativeTextPalette) {
        self.palette = palette
        refreshInk()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshInk()
    }

    private func refreshInk() {
        let ink = palette ?? NativeTextPalette(theme: .system,
            isDark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        statusLabel.textColor = ink.muted
        statusLabel.font = ink.mutedUsesSizeCue ? PreviewChrome.factsFont() : NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }
    @objc private func togglePlayback() { if player.isPlaying { player.pause() } else { player.play() } }
    @objc private func seek() { player.seek(to: positionSlider.doubleValue) }
    private func update(seconds: Double, playing: Bool) {
        playButton.title = PreviewStrings.text(playing ? .midiPause : .midiPlay)
        playButton.toolTip = playButton.title
        positionSlider.doubleValue = seconds
        timeLabel.stringValue = PreviewStrings.format(.midiPositionValue, arguments: [durationText(seconds), durationText(duration)])
        timeLabel.toolTip = timeLabel.stringValue.isEmpty ? nil : timeLabel.stringValue
        positionSlider.setAccessibilityValueDescription(durationText(seconds))
    }
    private func durationText(_ value: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: max(0, value)) ?? ""
    }
}
