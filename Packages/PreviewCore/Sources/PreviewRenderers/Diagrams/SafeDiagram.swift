import CoreGraphics
import Foundation
import PreviewContracts

/// A parsed and laid-out diagram, derived only from already-concealed source text.
///
/// This is the module's diagram API. `parse(mermaid:)` and `parse(drawio:)` read concealed text and
/// return nil for unsupported diagram types, syntax errors and documents beyond the limits in
/// `DiagramLimits`; callers then keep the Source presentation. A diagram draws through
/// `draw(in:size:palette:)` into any `CGContext` without an AppKit view, so a Markdown figure or a
/// thumbnail can reuse it. Parsing, layout and drawing are bounded and deterministic, and perform
/// no file, network or script access.
public struct SafeDiagram: Equatable, Sendable {
    public enum Kind: String, Sendable { case flowchart, state, classDiagram, entityRelationship, sequence, pie, drawio }

    let model: DiagramModel
    let scene: DiagramScene
    let accessibilityNodes: [DiagramAccessibilityNode]
    let connections: [DiagramConnection]
    /// The font and locale this layout was measured with.
    public let environment: DiagramEnvironment
    /// Identifies one parsed diagram, so views reset zoom only when the content changes.
    public let generation = UUID()

    init(model: DiagramModel, environment: DiagramEnvironment) throws {
        let result: DiagramLayoutResult
        let role: DiagramNodeRole
        switch model {
        case .flowchart(let graph):
            role = .node
            result = try GraphLayout.layout(graph, environment: environment, nodeRole: role)
        case .state(let graph):
            role = .state
            result = try GraphLayout.layout(graph, environment: environment, nodeRole: role)
        case .classDiagram(let graph):
            role = .classType
            result = try GraphLayout.layout(graph, environment: environment, nodeRole: role)
        case .entityRelationship(let graph):
            role = .entity
            result = try GraphLayout.layout(graph, environment: environment, nodeRole: role)
        case .sequence(let sequence): result = try SequenceLayout.layout(sequence, environment: environment)
        case .pie(let pie): result = try PieLayout.layout(pie, environment: environment)
        case .drawio(let page): result = try DrawioLayout.layout(page, environment: environment)
        }
        guard result.scene.size.width > 0, result.scene.size.height > 0 else { throw DiagramFailure.malformed }
        self.model = model
        self.scene = result.scene
        self.accessibilityNodes = result.nodes
        self.connections = result.connections
        self.environment = environment
    }

    public static func == (lhs: SafeDiagram, rhs: SafeDiagram) -> Bool {
        lhs.model == rhs.model && lhs.scene == rhs.scene && lhs.environment == rhs.environment
    }

    // MARK: Parsing

    /// Parses concealed Mermaid source: flowcharts, sequence diagrams, pie charts and state diagrams.
    public static func parse(mermaid safeSource: String, environment: DiagramEnvironment = DiagramEnvironment()) -> SafeDiagram? {
        guard let model = try? MermaidParser.parse(safeSource) else { return nil }
        return try? SafeDiagram(model: model, environment: environment)
    }

    /// Parses the concealed `mxGraphModel` XML the draw.io adapter produces for the first page.
    public static func parse(drawio safeSource: String, environment: DiagramEnvironment = DiagramEnvironment()) -> SafeDiagram? {
        guard let model = try? DrawioParser.parse(safeSource) else { return nil }
        return try? SafeDiagram(model: .drawio(model), environment: environment)
    }

    /// The same diagram measured with another font or locale, for typography and language changes.
    public func laidOut(with environment: DiagramEnvironment) -> SafeDiagram? {
        if environment == self.environment { return self }
        return try? SafeDiagram(model: model, environment: environment)
    }

    // MARK: Facts

    public var kind: Kind {
        switch model {
        case .flowchart: .flowchart
        case .state: .state
        case .classDiagram: .classDiagram
        case .entityRelationship: .entityRelationship
        case .sequence: .sequence
        case .pie: .pie
        case .drawio: .drawio
        }
    }

    /// Size of the drawing in scene points, including its margin.
    public var contentSize: CGSize { scene.size }
    public var nodeCount: Int { accessibilityNodes.count }
    public var connectionCount: Int { connections.count }

    // MARK: Drawing

    /// Draws the whole diagram scaled to fit `size`, centered, on the palette's background. The
    /// context is assumed to use the platform default (y up) unless `isFlipped` says it is already
    /// y down, as inside a flipped `NSView`. Content is never scaled up past twice its natural size.
    public func draw(in context: CGContext, size: CGSize, palette: DiagramPalette, isFlipped: Bool = false) {
        guard size.width > 0, size.height > 0, scene.size.width > 0, scene.size.height > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(palette.background.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        if !isFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        let scale = min(size.width / scene.size.width, size.height / scene.size.height, 2)
        context.translateBy(x: (size.width - scene.size.width * scale) / 2, y: (size.height - scene.size.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        DiagramDrawing.draw(scene, in: context, palette: palette, font: environment.font)
    }
}

/// Which formats a view should open in the Diagram mode.
enum SafeDiagramFormats {
    static let all: Set<FormatID> = [.mermaid, .drawio]
}
