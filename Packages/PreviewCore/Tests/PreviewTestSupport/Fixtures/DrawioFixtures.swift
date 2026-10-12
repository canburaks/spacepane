import Compression
import Foundation

/// Synthetic draw.io documents built in memory. Compression is done with the system framework, so
/// the tests exercise the same raw DEFLATE format that diagrams.net writes.
public enum DrawioFixtures {
    public static let cells = """
    <mxCell id="0"/><mxCell id="1" parent="0"/>\
    <mxCell id="2" value="Start" style="ellipse;whiteSpace=wrap;html=1;" vertex="1" parent="1"><mxGeometry x="40" y="40" width="100" height="60" as="geometry"/></mxCell>\
    <mxCell id="3" value="Finish" style="rounded=1;" vertex="1" parent="1"><mxGeometry x="240" y="40" width="100" height="60" as="geometry"/></mxCell>\
    <mxCell id="4" value="go" style="endArrow=classic;" edge="1" parent="1" source="2" target="3"><mxGeometry relative="1" as="geometry"><Array as="points"><mxPoint x="190" y="20"/></Array></mxGeometry></mxCell>
    """

    public static func model(_ cells: String = cells) -> String {
        "<mxGraphModel dx=\"800\" dy=\"400\"><root>\(cells)</root></mxGraphModel>"
    }

    public static func rawDeflate(_ data: Data) -> Data {
        let capacity = data.count + data.count / 2 + 1_024
        var output = [UInt8](repeating: 0, count: capacity)
        let size = data.withUnsafeBytes { input -> Int in
            guard let source = input.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(&output, capacity, source, data.count, nil, COMPRESSION_ZLIB)
        }
        return Data(output.prefix(size))
    }

    /// draw.io's page encoding: percent-encoded XML, raw DEFLATE, base64.
    public static func compressedPage(_ xml: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        let encoded = xml.addingPercentEncoding(withAllowedCharacters: allowed) ?? xml
        return rawDeflate(Data(encoded.utf8)).base64EncodedString()
    }

    public static func file(compressedPages pages: [String]) -> String {
        "<mxfile host=\"test\">" + pages.enumerated().map { index, page in
            "<diagram id=\"page-\(index)\" name=\"Page-\(index + 1)\">\(compressedPage(page))</diagram>"
        }.joined() + "</mxfile>"
    }

    public static func file(inlinePages pages: [String]) -> String {
        "<mxfile host=\"test\">" + pages.enumerated().map { index, page in
            "<diagram id=\"page-\(index)\" name=\"Page-\(index + 1)\">\(page)</diagram>"
        }.joined() + "</mxfile>"
    }
}
