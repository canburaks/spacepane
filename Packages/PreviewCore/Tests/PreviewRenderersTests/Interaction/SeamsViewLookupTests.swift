import AppKit
import Testing

/// The shared lookup that replaced the direct-subview searches in the renderer tests: it finds views by type at
/// any depth, shallowest first, in a plain view tree that has nothing to do with the preview's own layout.
@Suite("View lookup helper", .serialized)
@MainActor
struct SeamsViewLookupTests {
    @Test func theShallowestMatchComesFirstAndSiblingsKeepTheirOrder() {
        let root = NSView()
        let container = NSView()
        container.addSubview(NSTextField(labelWithString: "nested"))
        root.addSubview(container)
        root.addSubview(NSTextField(labelWithString: "first"))
        root.addSubview(NSTextField(labelWithString: "second"))
        #expect(descendants(of: NSTextField.self, in: root).map(\.stringValue) == ["first", "second", "nested"])
    }

    @Test func levelsAreVisitedInOrderAcrossBranches() {
        let root = NSView()
        let left = NSView()
        let right = NSView()
        root.addSubview(left)
        root.addSubview(right)
        let holder = NSView()
        left.addSubview(holder)
        holder.addSubview(NSTextField(labelWithString: "left grandchild"))
        left.addSubview(NSTextField(labelWithString: "left child"))
        right.addSubview(NSTextField(labelWithString: "right child"))
        #expect(descendants(of: NSTextField.self, in: root).map(\.stringValue)
                == ["left child", "right child", "left grandchild"])
    }

    @Test func theSearchedViewItselfIsNeverPartOfTheResult() {
        let root = NSView()
        let child = NSView()
        root.addSubview(child)
        let found = descendants(of: NSView.self, in: root)
        #expect(found.count == 1 && found.first === child)
        #expect(descendants(of: NSView.self, in: child).isEmpty)
    }

    @Test func aBaseTypeMatchesItsSubclassesAndHiddenViewsAreIncluded() {
        let root = NSView()
        let button = NSButton()
        button.isHidden = true
        root.addSubview(button)
        root.addSubview(NSView())
        #expect(descendants(of: NSControl.self, in: root).first === button)
        #expect(descendants(of: NSButton.self, in: root).first === button)
        #expect(descendants(of: NSScrollView.self, in: root).isEmpty)
    }
}
