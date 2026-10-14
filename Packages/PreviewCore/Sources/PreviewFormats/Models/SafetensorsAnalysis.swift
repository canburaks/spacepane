import Foundation
import PreviewContracts

/// Facts derived from a safetensors header's tensor descriptors: sizes, layout and naming conventions.
struct SafetensorsAnalysis {
    /// Sum of the tensors' element counts. A scalar (empty shape) has one element.
    private(set) var parameters: UInt64 = 0
    /// The largest `end` offset: the number of data bytes the descriptors account for.
    private(set) var dataBytes: UInt64 = 0
    /// Tensors whose range ends beyond the file's last byte.
    private(set) var tensorsBeyondFile = 0
    /// Tensors that do not start where the previous range ended (an overlap or a hole), whose size
    /// disagrees with their dtype and shape, plus one when bytes follow the last tensor.
    private(set) var inconsistentEntries = 0
    /// Tensors per dtype name.
    private(set) var dtypeCounts: [String: Int] = [:]
    /// Elements per tensor, in header order.
    private(set) var elementCounts: [UInt64] = []

    /// - Parameter availableBytes: bytes in the file after the header.
    init(tensors: [SafetensorsTensor], availableBytes: UInt64, context: RequestContext) throws {
        var flagged = [Bool](repeating: false, count: tensors.count)
        elementCounts.reserveCapacity(tensors.count)
        for (index, tensor) in tensors.enumerated() {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            dtypeCounts[tensor.dtype, default: 0] += 1
            var elements: UInt64 = 1
            for dimension in tensor.shape {
                let (product, overflow) = elements.multipliedReportingOverflow(by: dimension)
                guard !overflow else { throw PreviewFailure.malformedDocument }
                elements = product
            }
            let (total, overflow) = parameters.addingReportingOverflow(elements)
            guard !overflow else { throw PreviewFailure.malformedDocument }
            parameters = total
            elementCounts.append(elements)
            dataBytes = max(dataBytes, tensor.end)
            if tensor.end > availableBytes { tensorsBeyondFile += 1 }
            if let bits = Self.bitsPerElement(tensor.dtype) {
                let (totalBits, bitsOverflow) = elements.multipliedReportingOverflow(by: UInt64(bits))
                guard !bitsOverflow else { throw PreviewFailure.malformedDocument }
                if totalBits % 8 != 0 || totalBits / 8 != tensor.end - tensor.begin { flagged[index] = true }
            }
        }
        try context.checkpoint()
        let order = tensors.indices.sorted {
            (tensors[$0].begin, tensors[$0].end) < (tensors[$1].begin, tensors[$1].end)
        }
        try context.checkpoint()
        var covered: UInt64 = 0
        for index in order {
            if tensors[index].begin != covered { flagged[index] = true }
            covered = max(covered, tensors[index].end)
        }
        inconsistentEntries = flagged.lazy.filter { $0 }.count
        if tensorsBeyondFile == 0, availableBytes > dataBytes { inconsistentEntries += 1 }
    }

    /// Bits per element of the dtype names the safetensors library defines; `nil` for any other name,
    /// which is then left out of the size check.
    static func bitsPerElement(_ dtype: String) -> Int? {
        switch dtype {
        case "F4": 4
        case "F6_E2M3", "F6_E3M2": 6
        case "BOOL", "U8", "I8", "F8_E5M2", "F8_E4M3", "F8_E8M0", "F8_E4M3FNUZ", "F8_E5M2FNUZ": 8
        case "I16", "U16", "F16", "BF16": 16
        case "I32", "U32", "F32": 32
        case "I64", "U64", "F64", "C64": 64
        default: nil
        }
    }
}

/// Naming conventions that identify adapters and quantized checkpoints. Both are recognized from tensor
/// names and shapes alone, and only when the evidence is clear.
enum SafetensorsConventions {
    /// "LoRA" when the names hold both halves of a low-rank pair: PEFT's `lora_A` and `lora_B` or
    /// kohya's `lora_down` and `lora_up` (an `.alpha` tensor alone proves nothing).
    static func adapterKind(_ tensors: [SafetensorsTensor]) -> String? {
        var hasDown = false
        var hasUp = false
        for tensor in tensors {
            hasDown = hasDown || isDown(tensor.name)
            hasUp = hasUp || isUp(tensor.name)
            if hasDown, hasUp { return "LoRA" }
        }
        return nil
    }

    /// The rank when every down-projection (`lora_A`, `lora_down`) agrees on it; otherwise the rank the
    /// up-projections agree on; otherwise `nil`.
    static func loraRank(_ tensors: [SafetensorsTensor]) -> Int? {
        let down = Set(tensors.filter { isDown($0.name) && $0.shape.count >= 2 }.map { $0.shape[0] })
        let up = Set(tensors.filter { isUp($0.name) && $0.shape.count >= 2 }.map { $0.shape[1] })
        for ranks in [down, up] where ranks.count == 1 {
            if let rank = ranks.first, (1...65_536).contains(rank) { return Int(rank) }
        }
        return nil
    }

    private static func isDown(_ name: String) -> Bool { name.contains("lora_A") || name.contains("lora_down") }
    private static func isUp(_ name: String) -> Bool { name.contains("lora_B") || name.contains("lora_up") }

    /// "GPTQ" when a `.qweight` has `.scales` and `.g_idx` siblings; "AWQ" when it has `.scales` and
    /// `.qzeros` siblings and no `.g_idx`; `nil` if neither kind of module is present or both are.
    static func quantization(_ tensors: [SafetensorsTensor]) -> String? {
        let suffixes = [".qweight", ".scales", ".qzeros", ".g_idx"]
        var names = Set<String>()
        var packed: [String] = []
        for tensor in tensors {
            guard let suffix = suffixes.first(where: { tensor.name.hasSuffix($0) }) else { continue }
            names.insert(tensor.name)
            if suffix == ".qweight" { packed.append(String(tensor.name.dropLast(suffix.count))) }
        }
        let gptq = packed.contains { names.contains($0 + ".scales") && names.contains($0 + ".g_idx") }
        let awq = packed.contains {
            names.contains($0 + ".scales") && names.contains($0 + ".qzeros") && !names.contains($0 + ".g_idx")
        }
        switch (gptq, awq) {
        case (true, false): return "GPTQ"
        case (false, true): return "AWQ"
        default: return nil
        }
    }

    /// The position and size of a shard set from a Hugging Face shard name such as
    /// `model-00002-of-00005.safetensors` (index 2, count 5).
    static func shard(fromFileName fileName: String?) -> (index: Int, count: Int)? {
        guard var name = fileName?.lowercased(), name.hasSuffix(".safetensors") else { return nil }
        name.removeLast(".safetensors".count)
        let parts = name.components(separatedBy: "-of-")
        guard parts.count == 2, let total = Int(parts[1]), parts[1].allSatisfy({ $0.isASCII && $0.isNumber }), total > 0,
              let digits = parts[0].split(separator: "-").last, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let index = Int(digits), (1...total).contains(index), total <= 99_999 else { return nil }
        return (index, total)
    }
}
