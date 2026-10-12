import AppKit

// MARK: Key positions

/// Physical key positions as `NSEvent.keyCode` reports them, named after Carbon's `kVK_*` constants
/// (HIToolbox, Events.h), which this package does not import. A position does not change with the keyboard
/// layout; the character a key types does, and that difference is what the matching below is built around.
enum PreviewKeyCode {
    /// `kVK_ANSI_0` ... `kVK_ANSI_9`, indexed by the digit printed on the number-row key.
    static let numberRow: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
    /// `kVK_ANSI_Keypad0` ... `kVK_ANSI_Keypad9`, indexed by digit.
    static let keypad: [UInt16] = [82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
    /// `kVK_ANSI_C`, `kVK_ANSI_F`, `kVK_ANSI_G`, `kVK_ANSI_L` and `kVK_ANSI_R`: where those letters sit on a US
    /// keyboard, which is where a layout without Latin letters keeps its Command shortcuts.
    static let ansiC: UInt16 = 8
    static let ansiF: UInt16 = 3
    static let ansiG: UInt16 = 5
    static let ansiL: UInt16 = 37
    static let ansiR: UInt16 = 15
    /// `kVK_Return` and `kVK_ANSI_KeypadEnter`.
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    /// `kVK_Space` and `kVK_Escape`: the keys Quick Look owns.
    static let space: UInt16 = 49
    static let escape: UInt16 = 53

    /// The digit a number-row or keypad key carries, or nil for any other key.
    static func digit(forKeyCode keyCode: UInt16) -> Int? {
        numberRow.firstIndex(of: keyCode) ?? keypad.firstIndex(of: keyCode)
    }
}

// MARK: Key input

/// What a key-down event says, reduced to the values shortcut matching needs. Built from an event, or from
/// plain values where a test or an older call site has no event.
struct PreviewKeyInput {
    /// `NSEvent.charactersIgnoringModifiers`, lowercased: what the key types with only Shift applied.
    let typed: String
    /// `NSEvent.characters`, lowercased: what the key produced with every modifier applied. On a layout that
    /// keeps Latin letters for Command shortcuts this stays Latin when `typed` is not.
    let produced: String
    /// The key's position. Nil for a character-only input, which then can only be matched by its characters.
    let keyCode: UInt16?
    /// Only Command, Shift, Option and Control; caps lock, the keypad flag and the function flag never matter.
    let modifiers: NSEvent.ModifierFlags

    init(charactersIgnoringModifiers: String?, characters: String? = nil, keyCode: UInt16? = nil,
         modifiers: NSEvent.ModifierFlags) {
        typed = charactersIgnoringModifiers?.lowercased() ?? ""
        produced = characters?.lowercased() ?? ""
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .shift, .option, .control])
    }

    /// The input of a key-down event. Other event types carry no characters, so reading them would raise.
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        self.init(charactersIgnoringModifiers: event.charactersIgnoringModifiers, characters: event.characters,
                  keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    /// The one printable ASCII character `text` holds, or nil: no character, several, or anything outside
    /// printable ASCII (a Cyrillic, Greek, Arabic, Devanagari, Bengali or kana letter, a function-key code).
    static func asciiCharacter(in text: String) -> String? {
        var scalars = text.unicodeScalars.makeIterator()
        guard let scalar = scalars.next(), scalars.next() == nil, (0x21...0x7E).contains(scalar.value) else { return nil }
        return text
    }
}

// MARK: Key equivalents

/// One key chord: a key, the modifiers that must be held with it, and how the key is recognised.
struct PreviewKeyEquivalent: Equatable {
    enum Key: Equatable {
        /// A Latin letter, recognised by the character the key types. A layout that types no printable ASCII
        /// character for the key (Cyrillic, Greek, Arabic, Hindi, Bengali, kana) is recognised by the key's
        /// position instead, which is where macOS itself looks for such a layout's Command shortcuts. A Latin
        /// layout never uses the position, so Dvorak and AZERTY follow the letters on their keys.
        case letter(Character, position: UInt16)
        /// A digit, recognised by the number-row or keypad key first, because AZERTY types punctuation on the
        /// number row; a character-only input falls back to the typed digit.
        case digit(Int)
        /// Punctuation, recognised by the typed character only: its position differs on every layout.
        case symbols([String])
    }

    let key: Key
    let modifiers: NSEvent.ModifierFlags
    /// Whether Shift may also be held (the plus sign is a shifted equals on most layouts).
    let toleratesShift: Bool

    init(_ key: Key, modifiers: NSEvent.ModifierFlags = [], toleratesShift: Bool = false) {
        self.key = key
        self.modifiers = modifiers
        self.toleratesShift = toleratesShift
    }

    func matches(_ input: PreviewKeyInput) -> Bool {
        guard modifiers == input.modifiers || (toleratesShift && input.modifiers == modifiers.union(.shift)) else { return false }
        switch key {
        case .letter(let letter, let position):
            // The Command layer's character wins over the plain one: that is what a menu would match.
            let ascii = PreviewKeyInput.asciiCharacter(in: input.produced) ?? PreviewKeyInput.asciiCharacter(in: input.typed)
            guard let ascii else { return input.keyCode == position }
            return ascii == String(letter)
        case .digit(let digit):
            if let keyCode = input.keyCode, let carried = PreviewKeyCode.digit(forKeyCode: keyCode) { return carried == digit }
            return input.typed == String(digit)
        case .symbols(let accepted):
            guard let symbol = PreviewKeyInput.asciiCharacter(in: input.typed) else { return false }
            return accepted.contains(symbol)
        }
    }

    /// The character an `NSMenuItem` shows for this chord (lowercase; Shift is in the modifier mask).
    var menuKey: String {
        switch key {
        case .letter(let letter, _): String(letter)
        case .digit(let digit): String(digit)
        case .symbols(let accepted): accepted.first ?? ""
        }
    }

    /// The chord as Mac menus print it, modifiers in the order Control, Option, Shift, Command.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + menuKey.uppercased()
    }
}

// MARK: The command table

/// Every keyboard command the preview offers, in one table. The key chord, the title and the scope of each
/// command are defined here once; `PreviewShortcut`, the context menu and the shortcut list are derived from it.
///
/// Preview-scope commands are Command chords the preview answers while keyboard focus is inside it. Viewport
/// commands are the plain keys of the 3D viewport, which only the viewport answers while it has focus. Space and
/// Escape are in no table: Quick Look owns them (`PreviewKeyPolicy`).
enum PreviewCommand: Hashable, CaseIterable {
    /// Copies the selection (Command-C), which every content view does for itself.
    case copy
    /// Copies all the displayed concealed text (Shift-Command-C); `PreviewShortcut.copyAll`.
    case copyConcealed
    case find, findNext, findPrevious, goToLine
    /// The temporary text zoom: larger, smaller, and back to the saved size.
    case zoomIn, zoomOut, actualSize
    /// The nth view button (1 to 9) of the mode control, Option-Command-1 to Option-Command-9.
    case mode(Int)
    // Plain keys inside the 3D viewport.
    case fitModel, resetView, viewFront, viewSide, viewTop, cameraZoomIn, cameraZoomOut

    enum Scope: Equatable { case preview, viewport }

    /// The numbers the mode commands cover.
    static let modeNumbers = 1...9

    static let allCases: [PreviewCommand] = {
        var commands: [PreviewCommand] = [.copy, .copyConcealed, .find, .findNext, .findPrevious, .goToLine,
                                          .zoomIn, .zoomOut, .actualSize]
        for number in modeNumbers { commands.append(.mode(number)) }
        commands += [.fitModel, .resetView, .viewFront, .viewSide, .viewTop, .cameraZoomIn, .cameraZoomOut]
        return commands
    }()

    var scope: Scope {
        switch self {
        case .fitModel, .resetView, .viewFront, .viewSide, .viewTop, .cameraZoomIn, .cameraZoomOut: .viewport
        default: .preview
        }
    }

    /// The localized name the shortcut list and the context menu show. A mode command's key takes the number.
    var title: PreviewStrings.Key {
        switch self {
        case .copy: .interactionCopy
        case .copyConcealed: .interactionCopyAll
        case .find: .interactionFind
        case .findNext: .interactionFindNext
        case .findPrevious: .interactionFindPrevious
        case .goToLine: .interactionGoToLine
        case .zoomIn: .interactionZoomIn
        case .zoomOut: .interactionZoomOut
        case .actualSize: .interactionZoomReset
        case .mode: .interactionShowMode
        case .fitModel: .cadFit
        case .resetView: .cadReset
        case .viewFront: .cadFront
        case .viewSide: .cadSide
        case .viewTop: .cadTop
        case .cameraZoomIn: .cadZoomIn
        case .cameraZoomOut: .cadZoomOut
        }
    }

    var keyEquivalent: PreviewKeyEquivalent {
        switch self {
        case .copy: PreviewKeyEquivalent(.letter("c", position: PreviewKeyCode.ansiC), modifiers: .command)
        case .copyConcealed: PreviewKeyEquivalent(.letter("c", position: PreviewKeyCode.ansiC), modifiers: [.command, .shift])
        case .find: PreviewKeyEquivalent(.letter("f", position: PreviewKeyCode.ansiF), modifiers: .command)
        case .findNext: PreviewKeyEquivalent(.letter("g", position: PreviewKeyCode.ansiG), modifiers: .command)
        case .findPrevious: PreviewKeyEquivalent(.letter("g", position: PreviewKeyCode.ansiG), modifiers: [.command, .shift])
        case .goToLine: PreviewKeyEquivalent(.letter("l", position: PreviewKeyCode.ansiL), modifiers: .command)
        case .zoomIn: PreviewKeyEquivalent(.symbols(["+", "="]), modifiers: .command, toleratesShift: true)
        case .zoomOut: PreviewKeyEquivalent(.symbols(["-", "_"]), modifiers: .command, toleratesShift: true)
        case .actualSize: PreviewKeyEquivalent(.digit(0), modifiers: .command)
        case .mode(let number): PreviewKeyEquivalent(.digit(number), modifiers: [.option, .command])
        case .fitModel: PreviewKeyEquivalent(.letter("f", position: PreviewKeyCode.ansiF), toleratesShift: true)
        case .resetView: PreviewKeyEquivalent(.letter("r", position: PreviewKeyCode.ansiR), toleratesShift: true)
        case .viewFront: PreviewKeyEquivalent(.digit(1))
        case .viewSide: PreviewKeyEquivalent(.digit(2))
        case .viewTop: PreviewKeyEquivalent(.digit(3))
        case .cameraZoomIn: PreviewKeyEquivalent(.symbols(["+", "="]), toleratesShift: true)
        case .cameraZoomOut: PreviewKeyEquivalent(.symbols(["-", "_"]), toleratesShift: true)
        }
    }

    /// The chord as Mac menus print it, for tooltips and the shortcut list.
    var shortcutDescription: String { keyEquivalent.display }

    /// The title in the given language; the mode commands read "Show View 3".
    func localizedTitle(locale: Locale = .current, languagePreferences: [String]? = nil) -> String {
        switch self {
        case .mode(let number):
            return PreviewStrings.format(.interactionShowMode, arguments: [Int64(number)], locale: locale,
                                         languagePreferences: languagePreferences)
        default:
            return PreviewStrings.text(title, languagePreferences: languagePreferences)
        }
    }

    // MARK: Recognising a key

    /// The command a key event is, among the commands of `scope`. Nil for anything else and for non-key events.
    init?(event: NSEvent, scope: Scope = .preview) {
        guard let input = PreviewKeyInput(event: event) else { return nil }
        self.init(input: input, scope: scope)
    }

    /// The same from plain values, for callers and tests that have no event.
    init?(charactersIgnoringModifiers: String?, characters: String? = nil, keyCode: UInt16? = nil,
          modifiers: NSEvent.ModifierFlags, scope: Scope = .preview) {
        self.init(input: PreviewKeyInput(charactersIgnoringModifiers: charactersIgnoringModifiers, characters: characters,
                                         keyCode: keyCode, modifiers: modifiers), scope: scope)
    }

    init?(input: PreviewKeyInput, scope: Scope = .preview) {
        guard let match = Self.allCases.first(where: { $0.scope == scope && $0.keyEquivalent.matches(input) }) else { return nil }
        self = match
    }

    /// Find, Find Next and Find Previous: the commands a view without search answers with a spoken notice.
    var isFind: Bool {
        switch self {
        case .find, .findNext, .findPrevious: true
        default: false
        }
    }

    // MARK: Modes

    /// The 1-based position a mode command selects, or nil for any other command.
    var modeNumber: Int? {
        if case .mode(let number) = self { return number }
        return nil
    }

    /// The mode a mode command selects among the modes the control lists, in segment order. Nil for any other
    /// command, for a number past the last segment, and when the control has fewer than two segments (it is
    /// hidden then, so the keys stay free for whatever else wants them).
    func targetMode(among displayed: [NativePreviewMode]) -> NativePreviewMode? {
        guard let number = modeNumber, displayed.count > 1, displayed.indices.contains(number - 1) else { return nil }
        return displayed[number - 1]
    }
}

// MARK: Context menu

/// The target of a command menu item: runs the closure the host gave it. A menu item does not retain its
/// target, so the item keeps this object as its represented object.
@MainActor
final class PreviewCommandAction: NSObject {
    private let perform: @MainActor () -> Void

    init(_ perform: @escaping @MainActor () -> Void) {
        self.perform = perform
        super.init()
    }

    @objc func run(_ sender: Any?) { perform() }
}

extension PreviewCommand {
    /// The commands the text view's context menu lists, in order.
    static let contextMenuCommands: [PreviewCommand] = [.copyConcealed, .goToLine, .zoomIn, .zoomOut, .actualSize]

    /// A menu item with the command's title and key equivalent. The shortcut is shown for discovery; the preview
    /// answers the key itself, so the item is never triggered by it. `languagePreferences` exists for tests.
    @MainActor
    func menuItem(languagePreferences: [String]? = nil, perform: @escaping @MainActor () -> Void) -> NSMenuItem {
        let action = PreviewCommandAction(perform)
        let item = NSMenuItem(title: localizedTitle(languagePreferences: languagePreferences),
                              action: #selector(PreviewCommandAction.run(_:)), keyEquivalent: keyEquivalent.menuKey)
        item.keyEquivalentModifierMask = keyEquivalent.modifiers
        item.target = action
        item.representedObject = action
        return item
    }

    /// The items of `contextMenuCommands`; `perform` receives the command the user chose.
    @MainActor
    static func contextMenuItems(languagePreferences: [String]? = nil, includesGoToLine: Bool = true,
                                 perform: @escaping @MainActor (PreviewCommand) -> Void) -> [NSMenuItem] {
        contextMenuCommands.filter { includesGoToLine || $0 != .goToLine }.map { command in
            command.menuItem(languagePreferences: languagePreferences) { perform(command) }
        }
    }
}

// MARK: Key policy

/// Which keys the preview may bind (decision 027, amendment 10; owner decision D9). Space and Escape are never
/// bound: Quick Look closes on Space, so a view that has focus hands both on untouched. Arrow keys may act only
/// inside a content view that has keyboard focus (a table, an outline, the page column, a canvas or the 3D
/// viewport), never for the preview as a whole. Everything the preview itself answers is `PreviewCommand`.
enum PreviewKeyPolicy {
    /// Space and Escape.
    static func reservesForHost(keyCode: UInt16) -> Bool {
        keyCode == PreviewKeyCode.space || keyCode == PreviewKeyCode.escape
    }

    /// For a view that cannot search: when `event` is Find, Find Next or Find Previous, says so aloud and returns
    /// true, so the key is not silent. With no announcer the key is still answered, only unspoken. Returns false for
    /// any other event.
    @MainActor
    static func answerFindUnavailable(_ event: NSEvent, using announcer: PreviewAnnouncer?, from view: NSView) -> Bool {
        guard PreviewCommand(event: event)?.isFind == true else { return false }
        announcer?.announce(PreviewStrings.text(.interactionFindUnavailable), from: view)
        return true
    }
}

// MARK: Legacy shortcuts

/// The preview's own keyboard commands, recognised from a key-equivalent event, as `NativePreviewView` handles
/// them. It is the part of `PreviewCommand` that view acts on: every case is a preview-scope command, and a
/// command with no case here (the mode commands, Copy, the viewport keys) is handled elsewhere.
enum PreviewShortcut: Equatable {
    case goToLine, copyAll, find, findNext, findPrevious, zoomIn, zoomOut, zoomReset

    init?(event: NSEvent) {
        guard let command = PreviewCommand(event: event) else { return nil }
        self.init(command: command)
    }

    init?(characters: String?, modifiers: NSEvent.ModifierFlags) {
        guard let command = PreviewCommand(charactersIgnoringModifiers: characters, modifiers: modifiers) else { return nil }
        self.init(command: command)
    }

    init?(command: PreviewCommand) {
        switch command {
        case .goToLine: self = .goToLine
        case .copyConcealed: self = .copyAll
        case .find: self = .find
        case .findNext: self = .findNext
        case .findPrevious: self = .findPrevious
        case .zoomIn: self = .zoomIn
        case .zoomOut: self = .zoomOut
        case .actualSize: self = .zoomReset
        default: return nil
        }
    }

    var command: PreviewCommand {
        switch self {
        case .goToLine: .goToLine
        case .copyAll: .copyConcealed
        case .find: .find
        case .findNext: .findNext
        case .findPrevious: .findPrevious
        case .zoomIn: .zoomIn
        case .zoomOut: .zoomOut
        case .zoomReset: .actualSize
        }
    }
}
