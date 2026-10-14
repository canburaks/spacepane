import Foundation

/// Synthetic safetensors files assembled in code. Nothing here is a real model.
/// Sizes are written out independently of the production dtype table so a wrong constant in either place fails a test.
enum SafetensorsFixtures {
    struct Tensor {
        var name: String
        var dtype: String
        var shape: [UInt64]
        var begin: UInt64
        var end: UInt64
    }

    static func bytesPerElement(_ dtype: String) -> UInt64 {
        switch dtype {
        case "F32", "I32", "U32": 4
        case "F16", "BF16", "I16", "U16": 2
        case "I8", "U8", "BOOL", "F8_E4M3", "F8_E5M2": 1
        case "F64", "I64", "U64": 8
        default: preconditionFailure("fixture has no size for \(dtype)")
        }
    }

    /// Tensors placed one after the other with no gaps, as the library writes them.
    static func laidOut(_ specs: [(String, String, [UInt64])]) -> [Tensor] {
        var offset: UInt64 = 0
        return specs.map { name, dtype, shape in
            let size = shape.reduce(1, *) * bytesPerElement(dtype)
            defer { offset += size }
            return Tensor(name: name, dtype: dtype, shape: shape, begin: offset, end: offset + size)
        }
    }

    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case let control where control.value < 0x20: result += String(format: "\\u%04x", control.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    static func descriptor(_ tensor: Tensor) -> String {
        "{\"dtype\":\(quoted(tensor.dtype)),\"shape\":[\(tensor.shape.map(String.init).joined(separator: ","))],"
            + "\"data_offsets\":[\(tensor.begin),\(tensor.end)]}"
    }

    /// The header text: `__metadata__` first (as the library writes it), then the tensors in order.
    static func headerJSON(_ tensors: [Tensor], metadata: [(String, String)]? = nil, padding: Int = 0) -> String {
        var entries: [String] = []
        if let metadata {
            entries.append("\"__metadata__\":{" + metadata.map { "\(quoted($0.0)):\(quoted($0.1))" }.joined(separator: ",") + "}")
        }
        entries += tensors.map { "\(quoted($0.name)):\(descriptor($0))" }
        return "{" + entries.joined(separator: ",") + "}" + String(repeating: " ", count: padding)
    }

    /// Length prefix, header and `dataBytes` of zeros; `nil` writes exactly what the tensors need.
    static func file(header: Data, tensors: [Tensor] = [], dataBytes: Int? = nil, declaredLength: UInt64? = nil) -> Data {
        var data = Data()
        var length = declaredLength ?? UInt64(header.count)
        for _ in 0..<8 {
            data.append(UInt8(length & 0xFF))
            length >>= 8
        }
        data.append(header)
        data.append(Data(count: dataBytes ?? Int(tensors.map(\.end).max() ?? 0)))
        return data
    }

    static func file(json: String, tensors: [Tensor] = [], dataBytes: Int? = nil) -> Data {
        file(header: Data(json.utf8), tensors: tensors, dataBytes: dataBytes)
    }

    static func file(_ tensors: [Tensor], metadata: [(String, String)]? = nil, padding: Int = 0, dataBytes: Int? = nil) -> Data {
        file(json: headerJSON(tensors, metadata: metadata, padding: padding), tensors: tensors, dataBytes: dataBytes)
    }

    /// Two ordinary tensors: 32 F32 values and 8 BF16 values.
    static func ordinary(metadata: [(String, String)]? = [("format", "pt")]) -> Data {
        file(laidOut([("embed.weight", "F32", [4, 8]), ("norm.bias", "BF16", [8])]), metadata: metadata, padding: 5)
    }
}
