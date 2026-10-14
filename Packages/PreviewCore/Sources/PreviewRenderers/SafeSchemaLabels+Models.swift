import Foundation
import PreviewContracts

/// Summary schema written by the GGUF and safetensors adapters. Only the app-owned field names listed
/// here are translated. Model, author and organization names, licences, the chat template, tensor names,
/// tensor types and shapes, metadata keys and values and every other file-supplied string stay exactly as
/// stored; so do the keys of the type tables (`tensorTypes`, `dtypes`) and of the metadata objects.
extension SummaryLabelSet {
    static let models = SummaryLabelSet(
        formats: [.gguf, .safetensors],
        fields: { parent in
            switch parent {
            case []:
                return ["name", "architecture", "sizeLabel", "parameters", "fileType", "bitsPerWeight", "tensorTypes",
                        "contextLength", "blockCount", "embeddingLength", "headCount", "headCountKV", "expertCount",
                        "expertUsedCount", "vocabularySize", "tokenizer", "license", "author", "organization",
                        "quantizedBy", "baseModels", "tags", "languages", "chatTemplate", "chatTemplateBytes",
                        "ggufVersion", "alignment", "tensorCount", "metadataCount", "otherMetadata", "partial", "tensors",
                        "dtypes", "format", "shard", "adapterKind", "loraRank", "quantization", "headerBytes",
                        "dataBytes", "metadata"]
            case ["tensors", "[]"]: return ["name", "type", "dtype", "shape", "parameters"]
            default: return nil
            }
        },
        keys: [
            "name": .summaryName, "type": .summaryType, "partial": .dataPartial, "shape": .dataShape,
            "dtype": .dataDtype, "metadata": .dataMetadata, "format": .dataFormat,
            "architecture": .modelArchitecture, "sizeLabel": .modelSizeLabel, "parameters": .modelParameters,
            "fileType": .modelFileType, "bitsPerWeight": .modelBitsPerWeight, "tensorTypes": .modelTensorTypes,
            "contextLength": .modelContextLength, "blockCount": .modelBlockCount, "embeddingLength": .modelEmbeddingLength,
            "headCount": .modelHeadCount, "headCountKV": .modelHeadCountKV, "expertCount": .modelExpertCount,
            "expertUsedCount": .modelExpertUsedCount, "vocabularySize": .modelVocabularySize,
            "tokenizer": .modelTokenizer, "license": .modelLicense, "author": .modelAuthor,
            "organization": .modelOrganization, "quantizedBy": .modelQuantizedBy, "baseModels": .modelBaseModels,
            "tags": .modelTags, "languages": .modelLanguages, "chatTemplate": .modelChatTemplate,
            "chatTemplateBytes": .modelChatTemplateBytes, "ggufVersion": .modelGGUFVersion,
            "alignment": .modelAlignment, "tensorCount": .modelTensorCount, "metadataCount": .modelMetadataCount,
            "otherMetadata": .modelOtherMetadata, "tensors": .modelTensors, "dtypes": .modelDtypes,
            "shard": .modelShard, "adapterKind": .modelAdapterKind, "loraRank": .modelLoraRank,
            "quantization": .modelQuantization, "headerBytes": .modelHeaderBytes, "dataBytes": .modelDataBytes
        ],
        verbatimFields: ["name", "architecture", "sizeLabel", "fileType", "bitsPerWeight", "tokenizer", "license", "author",
                         "organization", "quantizedBy", "chatTemplate", "format", "shard", "adapterKind", "quantization",
                         "type", "dtype", "shape"],
        booleanFields: ["partial"],
        countFields: ["parameters", "contextLength", "blockCount", "embeddingLength", "headCount", "headCountKV",
                      "expertCount", "expertUsedCount", "vocabularySize", "chatTemplateBytes", "alignment",
                      "tensorCount", "metadataCount", "loraRank", "headerBytes", "dataBytes"])
}
