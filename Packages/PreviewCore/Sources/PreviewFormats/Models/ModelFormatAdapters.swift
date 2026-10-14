import PreviewContracts

/// Explicit registrations for the model-file formats of decision 030. Each reads only a header or the
/// pickle streams through the random-access path under the container-scan budget; weights are never read.
public enum ModelFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .gguf, defaultBudget: .containerScan, randomAccessAdapter: { GGUFAdapter() }),
        AdapterRegistration(formatID: .safetensors, defaultBudget: .containerScan, randomAccessAdapter: { SafetensorsAdapter() }),
        AdapterRegistration(formatID: .pickle, defaultBudget: .containerScan, randomAccessAdapter: { PickleAdapter() })
    ]
}
