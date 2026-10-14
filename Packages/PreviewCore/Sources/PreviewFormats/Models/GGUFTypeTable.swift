import Foundation

/// What a GGUF file's numeric codes mean, written from the public ggml and llama.cpp headers (both MIT
/// licensed; only the facts are used, no code). A code this table does not know is shown as `type N`
/// and left out of every size check, so a type added after this table was written never raises a
/// false finding.
enum GGUFTypeTable {
    /// One tensor storage type: `blockElements` values are stored in `blockBytes` bytes.
    struct TensorType: Equatable {
        let name: String
        let blockElements: Int
        let blockBytes: Int
    }

    private static let blockOfK = 256

    /// The `ggml_type` enum.
    private static let tensorTypes: [UInt32: TensorType] = {
        let table: [(UInt32, String, Int, Int)] = [
            (0, "F32", 1, 4), (1, "F16", 1, 2), (2, "Q4_0", 32, 18), (3, "Q4_1", 32, 20),
            (6, "Q5_0", 32, 22), (7, "Q5_1", 32, 24), (8, "Q8_0", 32, 34), (9, "Q8_1", 32, 36),
            (10, "Q2_K", blockOfK, 84), (11, "Q3_K", blockOfK, 110), (12, "Q4_K", blockOfK, 144),
            (13, "Q5_K", blockOfK, 176), (14, "Q6_K", blockOfK, 210), (15, "Q8_K", blockOfK, 292),
            (16, "IQ2_XXS", blockOfK, 66), (17, "IQ2_XS", blockOfK, 74), (18, "IQ3_XXS", blockOfK, 98),
            (19, "IQ1_S", blockOfK, 50), (20, "IQ4_NL", 32, 18), (21, "IQ3_S", blockOfK, 110),
            (22, "IQ2_S", blockOfK, 82), (23, "IQ4_XS", blockOfK, 136),
            (24, "I8", 1, 1), (25, "I16", 1, 2), (26, "I32", 1, 4), (27, "I64", 1, 8), (28, "F64", 1, 8),
            (29, "IQ1_M", blockOfK, 56), (30, "BF16", 1, 2),
            (34, "TQ1_0", blockOfK, 54), (35, "TQ2_0", blockOfK, 66),
            (39, "MXFP4", 32, 17), (40, "NVFP4", 64, 36), (41, "Q1_0", 128, 18), (42, "Q2_0", 64, 18)
        ]
        return Dictionary(uniqueKeysWithValues: table.map {
            ($0.0, TensorType(name: $0.1, blockElements: $0.2, blockBytes: $0.3))
        })
    }()

    static func tensorType(_ code: UInt32) -> TensorType? { tensorTypes[code] }

    /// The label shown for a tensor type: its name, or `type N` for a code this table does not know.
    static func label(_ code: UInt32) -> String { tensorTypes[code]?.name ?? "type \(code)" }

    /// Bytes a tensor of `elements` values occupies, or `nil` when the type is unknown, the first
    /// dimension is not a whole number of blocks (ggml refuses such a tensor) or the size overflows.
    static func byteCount(code: UInt32, elements: UInt64, firstDimension: UInt64) -> UInt64? {
        guard let type = tensorTypes[code], firstDimension % UInt64(type.blockElements) == 0 else { return nil }
        let blocks = elements / UInt64(type.blockElements)
        let (bytes, overflow) = blocks.multipliedReportingOverflow(by: UInt64(type.blockBytes))
        return overflow ? nil : bytes
    }

    /// Whether the type is known and its first dimension is not a whole number of blocks.
    static func hasPartialBlocks(code: UInt32, firstDimension: UInt64) -> Bool {
        guard let type = tensorTypes[code] else { return false }
        return firstDimension % UInt64(type.blockElements) != 0
    }

    /// `llama_ftype` values as `llama-quantize` names them. Removed codes are absent.
    private static let fileTypes: [UInt64: String] = [
        0: "F32", 1: "F16", 2: "Q4_0", 3: "Q4_1", 7: "Q8_0", 8: "Q5_0", 9: "Q5_1", 10: "Q2_K",
        11: "Q3_K_S", 12: "Q3_K_M", 13: "Q3_K_L", 14: "Q4_K_S", 15: "Q4_K_M", 16: "Q5_K_S", 17: "Q5_K_M",
        18: "Q6_K", 19: "IQ2_XXS", 20: "IQ2_XS", 21: "Q2_K_S", 22: "IQ3_XS", 23: "IQ3_XXS", 24: "IQ1_S",
        25: "IQ4_NL", 26: "IQ3_S", 27: "IQ3_M", 28: "IQ2_S", 29: "IQ2_M", 30: "IQ4_XS", 31: "IQ1_M",
        32: "BF16", 36: "TQ1_0", 37: "TQ2_0", 38: "MXFP4_MOE", 39: "NVFP4", 40: "Q1_0", 41: "Q2_0"
    ]

    /// The file type's name, or the number when the code is not one this table knows.
    static func fileTypeLabel(_ code: UInt64) -> String { fileTypes[code] ?? String(code) }
}
