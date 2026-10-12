import AppKit
import Foundation
import Testing
@testable import PreviewRenderers

/// A key-down event the way a key press delivers it on some layout: what the key types with only Shift applied,
/// what it produces with every modifier applied (the same unless a test says otherwise), and where the key sits.
@MainActor
private func modesKeyDown(typed: String, produced: String? = nil, keyCode: UInt16,
                          modifiers: NSEvent.ModifierFlags, type: NSEvent.EventType = .keyDown) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                  context: nil, characters: produced ?? typed, charactersIgnoringModifiers: typed,
                                  isARepeat: false, keyCode: keyCode))
}

/// The command table, its key-code matching and the legacy shortcut seen through it (decision 027, Q-38). Events
/// are synthetic: nothing here reads the keyboard, a preference or the user's clipboard.
@Suite("Preview command table")
@MainActor
struct ModesCommandTableTests {
    // MARK: The table

    @Test func everyCommandHasATitleAndAShortcutNoOtherCommandInItsScopeShares() {
        let unavailable = PreviewStrings.text(.resourceUnavailable, languagePreferences: ["en"])
        for scope in [PreviewCommand.Scope.preview, PreviewCommand.Scope.viewport] {
            let commands = PreviewCommand.allCases.filter { $0.scope == scope }
            #expect(!commands.isEmpty)
            let titles = commands.map { $0.localizedTitle(languagePreferences: ["en"]) }
            let shortcuts = commands.map(\.shortcutDescription)
            #expect(Set(titles).count == commands.count, "\(scope) titles: \(titles)")
            #expect(Set(shortcuts).count == commands.count, "\(scope) shortcuts: \(shortcuts)")
            for title in titles { #expect(!title.isEmpty && title != unavailable, "\(title)") }
        }
    }

    @Test func theTableListsItsCommandsInOrderWithTheirChords() {
        #expect(PreviewCommand.allCases.map(\.shortcutDescription) == [
            "⌘C", "⇧⌘C", "⌘F", "⌘G", "⇧⌘G", "⌘L", "⌘+", "⌘-", "⌘0",
            "⌥⌘1", "⌥⌘2", "⌥⌘3", "⌥⌘4", "⌥⌘5", "⌥⌘6", "⌥⌘7", "⌥⌘8", "⌥⌘9",
            "F", "R", "1", "2", "3", "+", "-"
        ])
        #expect(PreviewCommand.allCases.compactMap(\.modeNumber) == Array(1...9))
        // The scope follows the chord: Command chords belong to the preview, plain keys to the 3D viewport.
        for command in PreviewCommand.allCases {
            #expect((command.scope == .preview) == command.keyEquivalent.modifiers.contains(.command), "\(command)")
        }
    }

    @Test func englishTitlesReadAsMenuCommands() {
        func title(_ command: PreviewCommand) -> String { command.localizedTitle(languagePreferences: ["en"]) }
        #expect(title(.copy) == "Copy")
        #expect(title(.copyConcealed) == "Copy All")
        #expect(title(.find) == "Find")
        #expect(title(.findNext) == "Find Next")
        #expect(title(.findPrevious) == "Find Previous")
        #expect(title(.goToLine) == "Go to Line")
        #expect(title(.zoomIn) == "Zoom In")
        #expect(title(.zoomOut) == "Zoom Out")
        #expect(title(.actualSize) == "Actual Size")
        #expect(title(.mode(3)) == "Show View 3")
        #expect(title(.fitModel) == "Fit Model")
        #expect(title(.viewFront) == "Front")
        #expect(PreviewStrings.text(.interactionFindUnavailable, languagePreferences: ["en"]) == "Find is not available here")
    }

    @Test func everyCommandIsRecognisedFromItsOwnChordOnAUSKeyboardAndOnlyInItsScope() {
        for command in PreviewCommand.allCases {
            let equivalent = command.keyEquivalent
            let typed: String
            let keyCode: UInt16?
            switch equivalent.key {
            case .letter(let letter, let position): typed = String(letter); keyCode = position
            case .digit(let digit): typed = String(digit); keyCode = PreviewKeyCode.numberRow[digit]
            case .symbols(let accepted): typed = accepted[0]; keyCode = nil
            }
            let own = PreviewCommand(charactersIgnoringModifiers: typed, keyCode: keyCode, modifiers: equivalent.modifiers,
                                     scope: command.scope)
            #expect(own == command, "\(command)")
            let other: PreviewCommand.Scope = command.scope == .preview ? .viewport : .preview
            #expect(PreviewCommand(charactersIgnoringModifiers: typed, keyCode: keyCode, modifiers: equivalent.modifiers,
                                   scope: other) != command, "\(command)")
        }
    }

    @Test func theKeyCodeTablesHoldTenDistinctKeysEach() {
        #expect(PreviewKeyCode.numberRow.count == 10 && Set(PreviewKeyCode.numberRow).count == 10)
        #expect(PreviewKeyCode.keypad.count == 10 && Set(PreviewKeyCode.keypad).count == 10)
        #expect(Set(PreviewKeyCode.numberRow).isDisjoint(with: PreviewKeyCode.keypad))
        for digit in 0...9 {
            #expect(PreviewKeyCode.digit(forKeyCode: PreviewKeyCode.numberRow[digit]) == digit, "number row \(digit)")
            #expect(PreviewKeyCode.digit(forKeyCode: PreviewKeyCode.keypad[digit]) == digit, "keypad \(digit)")
        }
        #expect(PreviewKeyCode.digit(forKeyCode: PreviewKeyCode.space) == nil)
        // Anchors from HIToolbox/Events.h, written out so a wrong constant cannot agree with itself.
        #expect(PreviewKeyCode.numberRow[1] == 0x12 && PreviewKeyCode.numberRow[0] == 0x1D && PreviewKeyCode.keypad[0] == 0x52)
        #expect(PreviewKeyCode.ansiC == 0x08 && PreviewKeyCode.ansiF == 0x03 && PreviewKeyCode.ansiG == 0x05)
        #expect(PreviewKeyCode.ansiL == 0x25 && PreviewKeyCode.ansiR == 0x0F)
        #expect(PreviewKeyCode.space == 0x31 && PreviewKeyCode.escape == 0x35)
        #expect(PreviewKeyCode.returnKey == 0x24 && PreviewKeyCode.keypadEnter == 0x4C)
    }

    // MARK: Digits

    @Test func modeAndActualSizeKeysAreFoundByPositionOnLayoutsThatTypePunctuationOnTheNumberRow() throws {
        // French AZERTY types & é " ' ( § è ! ç à on the number row, so the typed character says nothing about the
        // digit; the position does. Option changes what the key produces, which must not matter either.
        let azerty = [1: "&", 2: "é", 3: "\"", 4: "'", 5: "(", 6: "§", 7: "è", 8: "!", 9: "ç", 0: "à"]
        for digit in 1...9 {
            let typed = try #require(azerty[digit])
            let press = try modesKeyDown(typed: typed, produced: "∞", keyCode: PreviewKeyCode.numberRow[digit],
                                         modifiers: [.option, .command])
            #expect(PreviewCommand(event: press) == .mode(digit), "AZERTY digit \(digit)")
        }
        let azertyZero = try modesKeyDown(typed: "à", keyCode: PreviewKeyCode.numberRow[0], modifiers: .command)
        #expect(PreviewCommand(event: azertyZero) == .actualSize)
        // The US layout types the digit itself.
        for digit in 1...9 {
            let press = try modesKeyDown(typed: String(digit), keyCode: PreviewKeyCode.numberRow[digit], modifiers: [.option, .command])
            #expect(PreviewCommand(event: press) == .mode(digit), "US digit \(digit)")
        }
        // The keypad counts too, and its flag is ignored.
        let keypadFive = try modesKeyDown(typed: "5", keyCode: PreviewKeyCode.keypad[5], modifiers: [.option, .command, .numericPad])
        #expect(PreviewCommand(event: keypadFive) == .mode(5))
        let keypadZero = try modesKeyDown(typed: "0", keyCode: PreviewKeyCode.keypad[0], modifiers: [.command, .numericPad])
        #expect(PreviewCommand(event: keypadZero) == .actualSize)
    }

    @Test func aDigitKeysPositionOutranksWhatItTypesAndOtherChordsAreLeftAlone() throws {
        // A 0 typed on the key that carries the 1: the position decides, so this is not Actual Size.
        let crossed = try modesKeyDown(typed: "0", keyCode: PreviewKeyCode.numberRow[1], modifiers: .command)
        #expect(PreviewCommand(event: crossed) == nil)
        // Without a key code (a character-only input) the typed digit decides.
        #expect(PreviewCommand(charactersIgnoringModifiers: "0", modifiers: .command) == .actualSize)
        #expect(PreviewCommand(charactersIgnoringModifiers: "4", modifiers: [.option, .command]) == .mode(4))
        // Command-digit belongs to Finder and Shift or Control chords are not ours; Option-Command-0 names no mode.
        let digitOne = PreviewKeyCode.numberRow[1]
        #expect(PreviewCommand(event: try modesKeyDown(typed: "1", keyCode: digitOne, modifiers: .command)) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "1", keyCode: digitOne, modifiers: [.shift, .option, .command])) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "1", keyCode: digitOne, modifiers: [.control, .option, .command])) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "0", keyCode: PreviewKeyCode.numberRow[0], modifiers: [.option, .command])) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "0", keyCode: PreviewKeyCode.numberRow[0], modifiers: [.shift, .command])) == nil)
    }

    // MARK: Letters

    @Test func lettersFollowTheLettersOnLatinLayoutsAndThePositionOnLayoutsWithoutThem() throws {
        // US.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "f", keyCode: PreviewKeyCode.ansiF, modifiers: .command)) == .find)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "c", keyCode: PreviewKeyCode.ansiC, modifiers: .command)) == .copy)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "C", keyCode: PreviewKeyCode.ansiC, modifiers: [.command, .shift])) == .copyConcealed)
        // Dvorak: the key that types F sits where QWERTY has Y (key code 16), and the QWERTY F position types U.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "f", keyCode: 16, modifiers: .command)) == .find)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "u", keyCode: PreviewKeyCode.ansiF, modifiers: .command)) == nil)
        // A Latin letter decides by its character even on another command's position.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "g", keyCode: PreviewKeyCode.ansiF, modifiers: .command)) == .findNext)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "G", keyCode: PreviewKeyCode.ansiF, modifiers: [.command, .shift])) == .findPrevious)
        // ASCII punctuation on a letter's position is still a character, never a position.
        #expect(PreviewCommand(event: try modesKeyDown(typed: ";", keyCode: PreviewKeyCode.ansiF, modifiers: .command)) == nil)
        // AZERTY keeps these letters where the US layout has them, and moves others: A and Q trade places.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "l", keyCode: PreviewKeyCode.ansiL, modifiers: .command)) == .goToLine)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "q", keyCode: 0, modifiers: .command)) == nil)
    }

    @Test func aLayoutWithoutLatinLettersIsReadByPosition() throws {
        // Russian: с а п д at the C, F, G and L positions.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "с", keyCode: PreviewKeyCode.ansiC, modifiers: .command)) == .copy)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "С", keyCode: PreviewKeyCode.ansiC, modifiers: [.command, .shift])) == .copyConcealed)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "а", keyCode: PreviewKeyCode.ansiF, modifiers: .command)) == .find)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "п", keyCode: PreviewKeyCode.ansiG, modifiers: .command)) == .findNext)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "П", keyCode: PreviewKeyCode.ansiG, modifiers: [.command, .shift])) == .findPrevious)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "д", keyCode: PreviewKeyCode.ansiL, modifiers: .command)) == .goToLine)
        // Kana and Devanagari are read the same way.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "は", keyCode: PreviewKeyCode.ansiF, modifiers: .command)) == .find)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "ब", keyCode: PreviewKeyCode.ansiL, modifiers: .command)) == .goToLine)
        // A letter off those positions is not a command, and the modifiers still have to match.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "ы", keyCode: 1, modifiers: .command)) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "д", keyCode: PreviewKeyCode.ansiL, modifiers: [.command, .option])) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "д", keyCode: PreviewKeyCode.ansiL, modifiers: [])) == nil)
        // A Command layer that stays Latin is read as the letter it produces, whatever the key types.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "а", produced: "f", keyCode: 99, modifiers: .command)) == .find)
    }

    @Test func zoomKeysAreMatchedByTheirCharacterOnly() throws {
        // French AZERTY types the minus on the key a US keyboard has the 6 on; the character is what counts.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "-", keyCode: PreviewKeyCode.numberRow[6], modifiers: .command)) == .zoomOut)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "_", keyCode: PreviewKeyCode.numberRow[6], modifiers: [.command, .shift])) == .zoomOut)
        // The plus is a shifted equals on most layouts: either spelling zooms in, with or without Shift.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "=", keyCode: 24, modifiers: .command)) == .zoomIn)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "+", keyCode: 24, modifiers: [.command, .shift])) == .zoomIn)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "+", keyCode: 69, modifiers: [.command, .numericPad])) == .zoomIn)
        // Option, Control and a missing Command are never zoom.
        #expect(PreviewCommand(event: try modesKeyDown(typed: "=", keyCode: 24, modifiers: [.command, .option])) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "=", keyCode: 24, modifiers: .control)) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "=", keyCode: 24, modifiers: [])) == nil)
    }

    @Test func spaceEscapeAndTheArrowsAreNeverCommands() throws {
        let arrow = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let keys: [(typed: String, keyCode: UInt16)] = [(" ", PreviewKeyCode.space), ("\u{1B}", PreviewKeyCode.escape), (arrow, 125)]
        let held: [NSEvent.ModifierFlags] = [[], .command, [.command, .shift], [.option, .command], .shift]
        for key in keys {
            for modifiers in held {
                let press = try modesKeyDown(typed: key.typed, keyCode: key.keyCode, modifiers: modifiers)
                #expect(PreviewCommand(event: press) == nil, "\(key.keyCode) with \(modifiers.rawValue)")
                #expect(PreviewCommand(event: press, scope: .viewport) == nil, "\(key.keyCode) with \(modifiers.rawValue)")
            }
        }
        #expect(PreviewKeyPolicy.reservesForHost(keyCode: PreviewKeyCode.space))
        #expect(PreviewKeyPolicy.reservesForHost(keyCode: PreviewKeyCode.escape))
        #expect(!PreviewKeyPolicy.reservesForHost(keyCode: 125))
        #expect(!PreviewKeyPolicy.reservesForHost(keyCode: PreviewKeyCode.returnKey))
    }

    // MARK: The 3D viewport

    @Test func theViewportKeysAreMatchedOnlyInTheViewportScope() throws {
        let plainF = try modesKeyDown(typed: "f", keyCode: PreviewKeyCode.ansiF, modifiers: [])
        #expect(PreviewCommand(event: plainF, scope: .viewport) == .fitModel)
        #expect(PreviewCommand(event: plainF) == nil)
        let commandF = try modesKeyDown(typed: "f", keyCode: PreviewKeyCode.ansiF, modifiers: .command)
        #expect(PreviewCommand(event: commandF) == .find)
        #expect(PreviewCommand(event: commandF, scope: .viewport) == nil)
        // Shift does not change a letter or a zoom key, and Option and Command are not the viewport's.
        let shiftedR = try modesKeyDown(typed: "R", keyCode: PreviewKeyCode.ansiR, modifiers: .shift)
        #expect(PreviewCommand(event: shiftedR, scope: .viewport) == .resetView)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "r", keyCode: PreviewKeyCode.ansiR, modifiers: .option), scope: .viewport) == nil)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "=", keyCode: 24, modifiers: []), scope: .viewport) == .cameraZoomIn)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "_", keyCode: 27, modifiers: .shift), scope: .viewport) == .cameraZoomOut)
        // The presets sit on the number row: AZERTY types an & there and a 1 only with Shift.
        let azertyOne = try modesKeyDown(typed: "&", keyCode: PreviewKeyCode.numberRow[1], modifiers: [])
        #expect(PreviewCommand(event: azertyOne, scope: .viewport) == .viewFront)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "é", keyCode: PreviewKeyCode.numberRow[2], modifiers: []), scope: .viewport) == .viewSide)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "3", keyCode: PreviewKeyCode.numberRow[3], modifiers: []), scope: .viewport) == .viewTop)
        #expect(PreviewCommand(event: try modesKeyDown(typed: "1", keyCode: PreviewKeyCode.numberRow[1], modifiers: .shift), scope: .viewport) == nil)
    }

    // MARK: The legacy shortcut

    @Test func theLegacyShortcutIsTheTableSeenThroughItsEightCases() {
        let pairs: [(PreviewShortcut, PreviewCommand)] = [
            (.goToLine, .goToLine), (.copyAll, .copyConcealed), (.find, .find), (.findNext, .findNext),
            (.findPrevious, .findPrevious), (.zoomIn, .zoomIn), (.zoomOut, .zoomOut), (.zoomReset, .actualSize)
        ]
        for (shortcut, command) in pairs {
            #expect(shortcut.command == command, "\(shortcut)")
            #expect(PreviewShortcut(command: command) == shortcut, "\(command)")
        }
        // What the preview handles elsewhere has no case: plain Copy, the mode chords and the viewport keys.
        for command in [PreviewCommand.copy, .mode(2), .fitModel, .viewFront, .cameraZoomIn] {
            #expect(PreviewShortcut(command: command) == nil, "\(command)")
        }
    }

    @Test func theShortcutReadsKeyCodesAndLayoutsFromEvents() throws {
        let azertyReset = try modesKeyDown(typed: "à", keyCode: PreviewKeyCode.numberRow[0], modifiers: .command)
        #expect(PreviewShortcut(event: azertyReset) == .zoomReset)
        let russianGoTo = try modesKeyDown(typed: "д", keyCode: PreviewKeyCode.ansiL, modifiers: .command)
        #expect(PreviewShortcut(event: russianGoTo) == .goToLine)
        let russianCopyAll = try modesKeyDown(typed: "С", keyCode: PreviewKeyCode.ansiC, modifiers: [.command, .shift])
        #expect(PreviewShortcut(event: russianCopyAll) == .copyAll)
        // A mode chord and plain Copy are commands, not shortcuts of the preview.
        #expect(PreviewShortcut(event: try modesKeyDown(typed: "1", keyCode: PreviewKeyCode.numberRow[1], modifiers: [.option, .command])) == nil)
        #expect(PreviewShortcut(event: try modesKeyDown(typed: "c", keyCode: PreviewKeyCode.ansiC, modifiers: .command)) == nil)
        // A key release is neither.
        let release = try modesKeyDown(typed: "l", keyCode: PreviewKeyCode.ansiL, modifiers: .command, type: .keyUp)
        #expect(PreviewShortcut(event: release) == nil)
        #expect(PreviewCommand(event: release) == nil)
    }

    // MARK: Modes

    @Test func aModeCommandSelectsTheNthDisplayedModeAndNothingElse() {
        let displayed: [NativePreviewMode] = [.source, .outline, .table]
        #expect(PreviewCommand.mode(1).targetMode(among: displayed) == .source)
        #expect(PreviewCommand.mode(3).targetMode(among: displayed) == .table)
        #expect(PreviewCommand.mode(4).targetMode(among: displayed) == nil)
        // One mode means no control, so the keys stay free.
        #expect(PreviewCommand.mode(1).targetMode(among: [.source]) == nil)
        #expect(PreviewCommand.zoomIn.targetMode(among: displayed) == nil)
        #expect(PreviewCommand.mode(2).modeNumber == 2)
        #expect(PreviewCommand.find.modeNumber == nil)
        #expect(PreviewCommand.mode(7).shortcutDescription == "⌥⌘7")
    }

    @Test func onlyFindCommandsAreFind() {
        let finds = PreviewCommand.allCases.filter(\.isFind)
        #expect(finds == [.find, .findNext, .findPrevious])
    }

    // MARK: Context menu

    @Test func theContextMenuIsBuiltFromTheTable() throws {
        var chosen: [PreviewCommand] = []
        let items = PreviewCommand.contextMenuItems(languagePreferences: ["en"]) { chosen.append($0) }
        #expect(items.map(\.title) == ["Copy All", "Go to Line", "Zoom In", "Zoom Out", "Actual Size"])
        #expect(items.map(\.keyEquivalent) == ["c", "l", "+", "-", "0"])
        let shifted: NSEvent.ModifierFlags = [.command, .shift]
        #expect(items.map(\.keyEquivalentModifierMask) == [shifted, .command, .command, .command, .command])
        #expect(PreviewCommand.contextMenuCommands == [.copyConcealed, .goToLine, .zoomIn, .zoomOut, .actualSize])
        // A menu item does not retain its target, so each item keeps its own action object; choosing it reports
        // the command the item stands for.
        for item in items {
            let action = try #require(item.representedObject as? PreviewCommandAction)
            #expect(item.target === action)
            action.run(item)
        }
        #expect(chosen == PreviewCommand.contextMenuCommands)
    }
}
