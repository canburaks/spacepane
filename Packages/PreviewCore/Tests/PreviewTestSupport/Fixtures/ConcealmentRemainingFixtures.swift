import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import PreviewContracts

/// Synthetic files used only by the second concealment-surface test tranche.
public struct ConcealmentRemainingFixture: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case environment, subtitle, archive, bibliography, geoJSON, parquet, notebook, application
    }
    public let kind: Kind
    public let formatID: FormatID
    public let fileName: String
    /// Relative paths and exact bytes. A directory fixture has more than one file here.
    public let files: [String: Data]
    public let sentinel: String
    public let forbiddenStrings: [String]
    /// These are intentionally encoded pictures, not text for OCR.
    public let encodedImages: [Data]
    /// GeoJSON deliberately omits property values before privacy filtering.
    public var expectsConcealment: Bool { kind != .geoJSON }
}

public enum ConcealmentRemainingFixtures {
    public static let sentinel = "Q151Safe"

    public static func make(_ kind: ConcealmentRemainingFixture.Kind,
                            sentinel requestedSentinel: String = ConcealmentRemainingFixtures.sentinel) throws -> ConcealmentRemainingFixture {
        let sentinel = requestedSentinel
        let values = ConcealmentFixtures.valueCanaries
        let token = ConcealmentFixtures.codeHostingCanary
        let forbidden = values + [token]
        func text(_ format: FormatID, _ name: String, _ source: String,
                  images: [Data] = []) -> ConcealmentRemainingFixture {
            .init(kind: kind, formatID: format, fileName: name, files: [name: Data(source.utf8)],
                  sentinel: sentinel, forbiddenStrings: forbidden, encodedImages: images)
        }
        switch kind {
        case .environment:
            let assignments = values.enumerated().map { "PASSWORD_\($0.offset)=\($0.element)" }.joined(separator: "\n")
            return text(.environment, "canary.env", "LABEL=\(sentinel)\n\(assignments)\nTOKEN=\(token)\n")
        case .subtitle:
            let cues = forbidden.enumerated().map { index, value in
                "\(index + 1)\n00:00:0\(index),000 --> 00:00:0\(index + 1),000\n\(sentinel)\npassword=\(value)\n"
            }.joined(separator: "\n")
            return text(.subRip, "canary.srt", cues)
        case .archive:
            let names = [sentinel + "/ordinary.txt"] + forbidden.map { "password=" + $0 + ".txt" }
            return .init(kind: kind, formatID: .tar, fileName: "canary.tar",
                         files: ["canary.tar": tar(names)], sentinel: sentinel,
                         forbiddenStrings: forbidden, encodedImages: [])
        case .bibliography:
            let entries = forbidden.enumerated().map { index, value in
                index < values.count
                    ? "@article{\(sentinel)\(index), title={\(sentinel)}, password={\(value)}, author={Reader, Alex}, year={2026}, journal={\(sentinel)}}"
                    : "@article{\(sentinel)\(index), title={\(sentinel) \(value)}, author={Reader, Alex}, year={2026}, journal={\(sentinel)}}"
            }.joined(separator: "\n")
            return text(.bibtex, "canary.bib", entries)
        case .geoJSON:
            // Values never enter this adapter's presentation; the property name does.
            let properties = Dictionary(uniqueKeysWithValues: forbidden.enumerated().map { ("value\($0.offset)", $0.element) })
                .merging([sentinel: sentinel]) { _, value in value }
            let object: [String: Any] = ["type": "Feature", "properties": properties,
                                        "geometry": ["type": "LineString", "coordinates": [[11.0, 22.0], [33.0, 44.0]]]]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            return .init(kind: kind, formatID: .geoJSON, fileName: "canary.geojson",
                         files: ["canary.geojson": data], sentinel: sentinel,
                         forbiddenStrings: forbidden, encodedImages: [])
        case .parquet:
            // Plain dictionary/data pages in the existing independent fixture. Replacements have
            // identical UTF-8 byte lengths, leaving every page length and footer offset intact.
            var data = DataFixtures.parquetRows
            let rowSentinel = requestedSentinel == Self.sentinel ? "Q151R" : requestedSentinel
            precondition(rowSentinel.utf8.count == 5)
            data = replacingBytes(Data("alpha".utf8), in: data, with: Data(rowSentinel.utf8))
            let original = Data(DataFixtures.secret.utf8)
            var cursor = data.startIndex
            for value in values {
                let replacement = Data((value + String(repeating: " ", count: original.count - value.utf8.count)).utf8)
                if let range = data.range(of: original, in: cursor..<data.endIndex) {
                    data.replaceSubrange(range, with: replacement)
                    cursor = range.upperBound
                }
            }
            return .init(kind: kind, formatID: .parquet, fileName: "canary.parquet",
                         files: ["canary.parquet": data], sentinel: rowSentinel,
                         forbiddenStrings: values, encodedImages: [])
        case .notebook:
            let source = [sentinel + "\n"] + forbidden.map { "password=" + $0 + "\n" }
            return try notebook(source: source, sentinel: sentinel, forbidden: forbidden)
        case .application:
            let png = try metadataPNG(forbidden)
            let info: [String: Any] = ["CFBundleName": sentinel, "CFBundleDisplayName": "password=" + values[0],
                "CFBundleIdentifier": "password=" + values[1], "CFBundleShortVersionString": "password=" + values[2],
                "CFBundleVersion": "password=" + values[3], "LSApplicationCategoryType": token, "CFBundleIconFile": "Canary"]
            let manifest = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            var member = Data("ic07".utf8); member += big(UInt32(png.count + 8)); member += png
            var icon = Data("icns".utf8); icon += big(UInt32(member.count + 8)); icon += member
            return .init(kind: kind, formatID: .applicationBundle, fileName: "Canary.app",
                         files: ["Canary.app/Contents/Info.plist": manifest,
                                 "Canary.app/Contents/Resources/Canary.icns": icon],
                         sentinel: sentinel, forbiddenStrings: forbidden, encodedImages: [png])
        }
    }

    /// A valid safe source beside the same canary-bearing image metadata. Its thumbnail must use cell
    /// text, not a saved figure; the ordinary notebook fixture separately exercises concealment fallback.
    public static func notebookWithSafeSourceAndImageMetadata() throws -> ConcealmentRemainingFixture {
        try notebook(source: [sentinel + "\n"], sentinel: sentinel,
                     forbidden: ConcealmentFixtures.valueCanaries + [ConcealmentFixtures.codeHostingCanary])
    }

    private static func notebook(source: [String], sentinel: String,
                                 forbidden: [String]) throws -> ConcealmentRemainingFixture {
        let png = try metadataPNG(forbidden)
        let object: [String: Any] = ["nbformat": 4, "nbformat_minor": 5, "metadata": [:], "cells": [
            ["cell_type": "code", "metadata": [:], "execution_count": NSNull(), "source": source,
             "outputs": [["output_type": "display_data", "metadata": [:], "data": [
                "image/png": png.base64EncodedString(), "text/plain": sentinel]]]]]]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return .init(kind: .notebook, formatID: .jupyterNotebook, fileName: "canary.ipynb",
                     files: ["canary.ipynb": data], sentinel: sentinel,
                     forbiddenStrings: forbidden, encodedImages: [png])
    }

    public static func replacingBytes(_ needle: Data, in source: Data, with replacement: Data) -> Data {
        precondition(needle.count == replacement.count && !needle.isEmpty)
        var data = source
        var cursor = data.startIndex
        while let range = data.range(of: needle, in: cursor..<data.endIndex) {
            data.replaceSubrange(range, with: replacement); cursor = range.upperBound
        }
        return data
    }

    /// An uncompressed UTF-8 PNG iTXt chunk, independent of ImageIO's property dictionary.
    private static func metadataPNG(_ strings: [String]) throws -> Data {
        let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let payload = Data("Comment\0\0\0\0\0".utf8) + Data(strings.joined(separator: "\n").utf8)
        let contents = Data("iTXt".utf8) + payload
        let chunk = big(UInt32(payload.count)) + contents + big(crc(contents))
        var png = output as Data
        png.insert(contentsOf: chunk, at: png.count - 12)
        return png
    }

    private static func big(_ value: UInt32) -> Data {
        Data([24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) })
    }
    private static func crc(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xFFFFFFFF
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = value & 1 == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1 }
        }
        return value ^ 0xFFFFFFFF
    }
    private static func tar(_ names: [String]) -> Data {
        var data = Data()
        for name in names {
            var block = [UInt8](repeating: 0, count: 512)
            let bytes = Array(name.utf8)
            precondition(bytes.count < 100)
            block.replaceSubrange(0..<bytes.count, with: bytes)
            func field(_ offset: Int, _ width: Int, _ value: Int) {
                let digits = String(value, radix: 8)
                let bytes = Array((String(repeating: "0", count: width - digits.count - 1) + digits + "\0").utf8)
                block.replaceSubrange(offset..<(offset + width), with: bytes)
            }
            field(100, 8, 420); field(108, 8, 0); field(116, 8, 0); field(124, 12, 0); field(136, 12, 0)
            block.replaceSubrange(148..<156, with: [UInt8](repeating: 32, count: 8))
            block[156] = 48
            block.replaceSubrange(257..<263, with: Array("ustar\0".utf8))
            block.replaceSubrange(263..<265, with: Array("00".utf8))
            let checksum = block.reduce(0) { $0 + Int($1) }
            let digits = String(checksum, radix: 8)
            block.replaceSubrange(148..<156, with: Array((String(repeating: "0", count: 6 - digits.count) + digits + "\0 ").utf8))
            data += Data(block)
        }
        data += Data(repeating: 0, count: 1024)
        return data
    }
}
