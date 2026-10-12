// Development-only public API probe. A generated image does not identify its provider.
// Compile with xcrun swiftc -parse-as-library script/probe_thumbnail.swift -o /tmp/prev-thumbnail-probe
// Run with a synthetic local input, a new output PNG path and optional settings, in any order after the paths:
//   <size>                                 square size in points, 64...1024 (default 256)
//   --scale <1...3>                        backing scale of the request (default 1; Retina is 2)
//   --icon-mode                            ask for the icon-style thumbnail (frame, curl, system badge)
//   --representation <icon|lowQuality|thumbnail|all>   which representations may answer (default thumbnail)
// Attribute the extension process/bundle separately; do not infer invocation from the image or clear
// shared caches. The line printed at the end repeats every setting, so a recorded image keeps its request.
//
// Content thumbnails (decision 022): for a catalog format whose thumbnail policy is `content`, the
// signed extension may draw a concealed excerpt, grid or document picture; every other file gets the
// content-free glyph. Which of the two appears here depends on the installed build, the saved
// "content thumbnails" switch and the file-type choices, and macOS may serve an older cached image.
// Use only synthetic inputs: a PNG written by this probe can contain whatever the thumbnail drew.
//
// Type badge (decision 027, Q-120): the extension sets QLThumbnailReply.extensionBadge to the catalog suffix
// of the file name. Whether and where macOS draws it is exactly what --icon-mode at --scale 2 records; compare
// the image with and without the flag, and with the badge's suffix changed, before designing anything drawn.
import AppKit
import QuickLookThumbnailing

@main struct ThumbnailProbe {
    private enum Representation: String {
        case icon, lowQuality, thumbnail, all

        var types: QLThumbnailGenerator.Request.RepresentationTypes {
            switch self {
            case .icon: .icon
            case .lowQuality: .lowQualityThumbnail
            case .thumbnail: .thumbnail
            case .all: .all
            }
        }
    }

    private struct Options {
        var side = 256.0
        var scale = 1.0
        var iconMode = false
        var representation = Representation.thumbnail
    }

    private static func parsedOptions(from arguments: ArraySlice<String>) throws -> Options {
        var options = Options()
        var remaining = arguments
        while let argument = remaining.first {
            remaining = remaining.dropFirst()
            switch argument {
            case "--icon-mode":
                options.iconMode = true
            case "--scale":
                guard let value = remaining.first, let scale = Double(value), (1...3).contains(scale) else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                options.scale = scale
                remaining = remaining.dropFirst()
            case "--representation":
                guard let value = remaining.first, let representation = Representation(rawValue: value) else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                options.representation = representation
                remaining = remaining.dropFirst()
            default:
                guard let side = Double(argument), (64...1024).contains(side) else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                options.side = side
            }
        }
        return options
    }

    @MainActor static func main() async throws {
        guard CommandLine.arguments.count >= 3 else { throw CocoaError(.fileReadInvalidFileName) }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let options = try parsedOptions(from: CommandLine.arguments.dropFirst(3))
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
        let request = QLThumbnailGenerator.Request(fileAt: input, size: NSSize(width: options.side, height: options.side),
                                                   scale: options.scale, representationTypes: options.representation.types)
        request.iconMode = options.iconMode
        let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        let bitmap = NSBitmapImageRep(cgImage: representation.cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: output, options: .withoutOverwriting)
        print("Generated \(representation.cgImage.width) × \(representation.cgImage.height), representation \(representation.type.rawValue). "
              + "Requested \(options.side) pt at scale \(options.scale), icon mode \(options.iconMode), "
              + "representations \(options.representation.rawValue). Verify provider attribution separately.")
    }
}
