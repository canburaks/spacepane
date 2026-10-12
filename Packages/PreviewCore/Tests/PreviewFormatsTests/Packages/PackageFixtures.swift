import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import zlib

/// Deterministic, fully synthetic fixtures for the package, certificate, disk-image and torrent
/// adapters. Nothing here is copied from a real application, profile, certificate or device, and no
/// value resembles a real credential. Builders are written independently of the production parsers.
enum PackageFixtures {
    /// A marker no concealed representation may ever contain.
    static let secret = "synthetic-secret-value"

    // MARK: Byte helpers

    static func little(_ value: UInt64, _ width: Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
    static func big(_ value: UInt64, _ width: Int) -> Data { Data((0..<width).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }

    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return UInt32(zlib.crc32(0, nil, 0)) }
            return UInt32(zlib.crc32(0, base, uInt(buffer.count)))
        }
    }

    /// zlib-wrapped deflate, as XAR stores `application/x-gzip` members.
    static func zlibCompress(_ data: Data) -> Data {
        var length = compressBound(uLong(data.count))
        var output = Data(count: Int(length))
        let status = output.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compress2(target.bindMemory(to: Bytef.self).baseAddress, &length, source.bindMemory(to: Bytef.self).baseAddress,
                          uLong(data.count), Z_BEST_COMPRESSION)
            }
        }
        precondition(status == Z_OK)
        return output.prefix(Int(length))
    }

    // MARK: Property lists

    static func plist(_ object: Any, binary: Bool = false) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: object, format: binary ? .binary : .xml, options: 0)
    }

    static func plistObject(_ data: Data) -> Any {
        try! PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    // MARK: ZIP

    /// A ZIP archive of stored (uncompressed) members with correct CRCs, sizes and offsets.
    static func zip(_ members: [(path: String, data: Data)]) -> Data {
        var archive = Data()
        var directory = Data()
        for member in members {
            let name = Data(member.path.utf8)
            let offset = archive.count
            let checksum = UInt64(crc32(member.data))
            archive += little(0x04034b50, 4) + little(20, 2) + little(0x800, 2) + little(0, 2) + little(0, 2) + little(0x21, 2)
            archive += little(checksum, 4) + little(UInt64(member.data.count), 4) + little(UInt64(member.data.count), 4)
            archive += little(UInt64(name.count), 2) + little(0, 2) + name + member.data
            directory += little(0x02014b50, 4) + little(20, 2) + little(20, 2) + little(0x800, 2) + little(0, 2) + little(0, 2) + little(0x21, 2)
            directory += little(checksum, 4) + little(UInt64(member.data.count), 4) + little(UInt64(member.data.count), 4)
            directory += little(UInt64(name.count), 2) + little(0, 2) + little(0, 2) + little(0, 2) + little(0, 2)
            directory += little(0, 4) + little(UInt64(offset), 4) + name
        }
        let start = archive.count
        archive += directory
        archive += little(0x06054b50, 4) + little(0, 2) + little(0, 2) + little(UInt64(members.count), 2) + little(UInt64(members.count), 2)
        archive += little(UInt64(directory.count), 4) + little(UInt64(start), 4) + little(0, 2)
        return archive
    }

    // MARK: Images

    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// An Apple icon container holding the given PNG representations.
    static func icns(_ elements: [(type: String, png: Data)]) -> Data {
        var body = Data()
        for element in elements { body += Data(element.type.utf8) + big(UInt64(8 + element.png.count), 4) + element.png }
        return Data("icns".utf8) + big(UInt64(8 + body.count), 4) + body
    }

    // MARK: Mach-O

    static let arm64CPU: UInt64 = 0x0100_000C
    static let x86_64CPU: UInt64 = 0x0100_0007

    static func thinMachO(cpu: UInt64) -> Data {
        // Little-endian 64-bit header: magic, cputype, cpusubtype, filetype, then padding.
        little(0xFEED_FACF, 4) + little(cpu, 4) + little(0, 4) + little(2, 4) + Data(repeating: 0, count: 64)
    }

    static func universalMachO(cpus: [UInt64]) -> Data {
        var data = big(0xCAFE_BABE, 4) + big(UInt64(cpus.count), 4)
        for cpu in cpus { data += big(cpu, 4) + big(0, 4) + big(0x4000, 4) + big(0x1000, 4) + big(14, 4) }
        return data + Data(repeating: 0, count: 64)
    }

    // MARK: DER

    enum DER {
        static func length(_ count: Int) -> Data {
            if count < 0x80 { return Data([UInt8(count)]) }
            if count < 0x100 { return Data([0x81, UInt8(count)]) }
            if count < 0x10000 { return Data([0x82, UInt8(count >> 8), UInt8(count & 0xFF)]) }
            return Data([0x83, UInt8(count >> 16), UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF)])
        }
        static func tlv(_ tag: UInt8, _ content: Data) -> Data { Data([tag]) + length(content.count) + content }
        static func sequence(_ parts: [Data]) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
        static func set(_ parts: [Data]) -> Data { tlv(0x31, parts.reduce(Data(), +)) }
        static func integer(_ value: Int) -> Data {
            var bytes = withUnsafeBytes(of: value.bigEndian, Array.init)
            while bytes.count > 1, (bytes[0] == 0 && bytes[1] & 0x80 == 0) || (bytes[0] == 0xFF && bytes[1] & 0x80 != 0) { bytes.removeFirst() }
            return tlv(0x02, Data(bytes))
        }
        static func oid(_ dotted: String) -> Data {
            let arcs = dotted.split(separator: ".").map { UInt64($0)! }
            var bytes: [UInt8] = [UInt8(arcs[0] * 40 + arcs[1])]
            for arc in arcs.dropFirst(2) {
                var chunk: [UInt8] = [UInt8(arc & 0x7F)]
                var rest = arc >> 7
                while rest > 0 { chunk.insert(UInt8(rest & 0x7F) | 0x80, at: 0); rest >>= 7 }
                bytes += chunk
            }
            return tlv(0x06, Data(bytes))
        }
        static func utf8(_ text: String) -> Data { tlv(0x0C, Data(text.utf8)) }
        static func printable(_ text: String) -> Data { tlv(0x13, Data(text.utf8)) }
        static func octetString(_ data: Data) -> Data { tlv(0x04, data) }
        static func bitString(_ data: Data) -> Data { tlv(0x03, Data([0]) + data) }
        static func utcTime(_ text: String) -> Data { tlv(0x17, Data(text.utf8)) }
        static func explicit(_ number: UInt8, _ content: Data) -> Data { tlv(0xA0 | number, content) }
        static func name(_ attributes: [(oid: String, value: String)]) -> Data {
            sequence(attributes.map { attribute in
                set([sequence([oid(attribute.oid), attribute.oid == "2.5.4.6" ? printable(attribute.value) : utf8(attribute.value)])])
            })
        }
    }

    // MARK: X.509

    /// A self-signed ECDSA P-256 certificate. The key is derived from a fixed phrase so output is
    /// deterministic, and it is used for nothing else.
    static func certificate(commonName: String = "example.test", organization: String = "Example Org",
                            notBefore: String = "260101000000Z", notAfter: String = "360101000000Z",
                            serial: Int = 0x1234_5678, dnsNames: [String] = ["example.test", "www.example.test"],
                            ipAddress: [UInt8]? = [127, 0, 0, 1]) -> Data {
        let key = try! P256.Signing.PrivateKey(rawRepresentation: Data(SHA256.hash(data: Data("synthetic-package-fixture-key".utf8))))
        let algorithm = DER.sequence([DER.oid("1.2.840.10045.4.3.2")])
        let subject = DER.name([("2.5.4.6", "US"), ("2.5.4.10", organization), ("2.5.4.3", commonName)])
        var general = dnsNames.map { DER.tlv(0x82, Data($0.utf8)) }
        if let ipAddress { general.append(DER.tlv(0x87, Data(ipAddress))) }
        let extensions = DER.explicit(3, DER.sequence([
            DER.sequence([DER.oid("2.5.29.17"), DER.octetString(DER.sequence(general))])
        ]))
        let tbs = DER.sequence([
            DER.explicit(0, DER.integer(2)), DER.integer(serial), algorithm, subject,
            DER.sequence([DER.utcTime(notBefore), DER.utcTime(notAfter)]), subject,
            key.publicKey.derRepresentation, extensions
        ])
        let signature = try! key.signature(for: tbs).derRepresentation
        return DER.sequence([tbs, algorithm, DER.bitString(signature)])
    }

    static func pem(label: String, body: Data, lineLength: Int = 64) -> String {
        let encoded = body.base64EncodedString()
        var lines: [String] = []
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let next = encoded.index(index, offsetBy: lineLength, limitedBy: encoded.endIndex) ?? encoded.endIndex
            lines.append(String(encoded[index..<next]))
            index = next
        }
        return "-----BEGIN \(label)-----\n" + lines.joined(separator: "\n") + "\n-----END \(label)-----\n"
    }

    // MARK: CMS

    /// A CMS SignedData message wrapping `content`. The signature bytes are placeholders: the code under
    /// test decodes the envelope and never verifies it.
    static func signedMessage(content: Data) -> Data {
        let sha256 = DER.sequence([DER.oid("2.16.840.1.101.3.4.2.1")])
        let signer = DER.sequence([
            DER.integer(1),
            DER.sequence([DER.name([("2.5.4.3", "Synthetic Signer")]), DER.integer(7)]),
            sha256, DER.sequence([DER.oid("1.2.840.10045.4.3.2")]), DER.octetString(Data(repeating: 0, count: 8))
        ])
        let signedData = DER.sequence([
            DER.integer(1), DER.set([sha256]),
            DER.sequence([DER.oid("1.2.840.113549.1.7.1"), DER.explicit(0, DER.octetString(content))]),
            DER.set([signer])
        ])
        return DER.sequence([DER.oid("1.2.840.113549.1.7.2"), DER.explicit(0, signedData)])
    }

    // MARK: Provisioning profiles

    static func profilePropertyList(name: String = "Synthetic Profile", devices: Int = 3, getTaskAllow: Bool = true,
                                    expiration: Date = Date(timeIntervalSince1970: 2_000_000_000),
                                    includeCertificate: Bool = true, extraEntitlements: [String: Any] = [:]) -> Data {
        var entitlements: [String: Any] = [
            "application-identifier": "ABCDE12345.com.example.synthetic", "get-task-allow": getTaskAllow,
            "com.apple.developer.team-identifier": "ABCDE12345"
        ]
        entitlements.merge(extraEntitlements) { $1 }
        var profile: [String: Any] = [
            "Name": name, "UUID": "00000000-0000-4000-8000-000000000001", "AppIDName": "Synthetic App",
            "TeamName": "Example Team", "TeamIdentifier": ["ABCDE12345"], "Platform": ["iOS"],
            "CreationDate": Date(timeIntervalSince1970: 1_700_000_000), "ExpirationDate": expiration,
            "Entitlements": entitlements,
            "ProvisionedDevices": (0..<devices).map { "synthetic-device-identifier-\($0)" }
        ]
        if includeCertificate { profile["DeveloperCertificates"] = [certificate(commonName: "Synthetic Developer")] }
        return plist(profile)
    }

    // MARK: Android binary XML

    enum AXMLValue {
        case string(String), integer(Int32), boolean(Bool), reference(UInt32)
    }

    struct AXMLAttribute {
        let name: String
        let resourceID: UInt32?
        let value: AXMLValue
        /// When true the attribute name string is stored empty so the resource id is the only name.
        var stripName = false
    }

    indirect enum AXMLNode {
        case element(String, [AXMLAttribute], [AXMLNode])
    }

    /// Compiled Android XML with a UTF-16 or UTF-8 string pool and a resource-id map.
    static func axml(_ root: AXMLNode, utf8: Bool = false) -> Data {
        // Resource-mapped attribute names occupy the leading string slots, as real packers emit them.
        var strings: [String] = []
        var resourceIDs: [UInt32] = []
        func mapNames(_ node: AXMLNode) {
            guard case let .element(_, attributes, children) = node else { return }
            for attribute in attributes {
                if let id = attribute.resourceID, !resourceIDs.contains(id) {
                    resourceIDs.append(id)
                    strings.append(attribute.stripName ? "" : attribute.name)
                }
            }
            children.forEach(mapNames)
        }
        mapNames(root)
        let seenIDs = resourceIDs
        func index(of string: String) -> UInt32 {
            if let existing = strings.firstIndex(of: string) { return UInt32(existing) }
            strings.append(string)
            return UInt32(strings.count - 1)
        }

        var chunks = Data()
        func emit(_ node: AXMLNode) {
            guard case let .element(name, attributes, children) = node else { return }
            let nameIndex = index(of: name)
            var attributeData = Data()
            for attribute in attributes {
                let mappedPosition = attribute.resourceID.flatMap { seenIDs.firstIndex(of: $0) }
                let nameSlot = mappedPosition.map { UInt32($0) } ?? index(of: attribute.name)
                var raw: UInt32 = 0xFFFF_FFFF
                var type: UInt8
                var data: UInt32
                switch attribute.value {
                case .string(let text): raw = index(of: text); type = 0x03; data = raw
                case .integer(let number): type = 0x10; data = UInt32(bitPattern: number)
                case .boolean(let flag): type = 0x12; data = flag ? 0xFFFF_FFFF : 0
                case .reference(let id): type = 0x01; data = id
                }
                attributeData += little(0xFFFF_FFFF, 4) + little(UInt64(nameSlot), 4) + little(UInt64(raw), 4)
                attributeData += little(8, 2) + Data([0, type]) + little(UInt64(data), 4)
            }
            let startSize = 36 + attributeData.count
            chunks += little(0x0102, 2) + little(16, 2) + little(UInt64(startSize), 4) + little(1, 4) + little(0xFFFF_FFFF, 4)
            chunks += little(0xFFFF_FFFF, 4) + little(UInt64(nameIndex), 4) + little(0x14, 2) + little(0x14, 2)
            chunks += little(UInt64(attributes.count), 2) + little(0, 2) + little(0, 2) + little(0, 2) + attributeData
            children.forEach(emit)
            chunks += little(0x0103, 2) + little(16, 2) + little(24, 4) + little(1, 4) + little(0xFFFF_FFFF, 4)
            chunks += little(0xFFFF_FFFF, 4) + little(UInt64(nameIndex), 4)
        }
        emit(root)

        // String pool: offsets then string data.
        var offsets = Data()
        var pool = Data()
        for string in strings {
            offsets += little(UInt64(pool.count), 4)
            if utf8 {
                let bytes = Data(string.utf8)
                pool += Data([UInt8(string.count)]) + Data([UInt8(bytes.count)]) + bytes + Data([0])
            } else {
                let units = Array(string.utf16)
                pool += little(UInt64(units.count), 2) + Data(units.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }) + little(0, 2)
            }
        }
        while pool.count % 4 != 0 { pool.append(0) }
        let stringsStart = 28 + offsets.count
        var poolChunk = little(0x0001, 2) + little(28, 2) + little(UInt64(28 + offsets.count + pool.count), 4)
        poolChunk += little(UInt64(strings.count), 4) + little(0, 4) + little(utf8 ? 0x100 : 0, 4)
        poolChunk += little(UInt64(stringsStart), 4) + little(0, 4) + offsets + pool
        var map = Data()
        for id in resourceIDs { map += little(UInt64(id), 4) }
        let mapChunk = little(0x0180, 2) + little(8, 2) + little(UInt64(8 + map.count), 4) + map
        let body = poolChunk + mapChunk + chunks
        return little(0x0003, 2) + little(8, 2) + little(UInt64(8 + body.count), 4) + body
    }

    /// A manifest with the framework attribute resource identifiers real packers emit.
    static func androidManifest(package: String = "com.example.synthetic", versionCode: Int32 = 42, versionName: String = "1.2.3",
                                minSDK: Int32 = 24, targetSDK: Int32 = 34, permissions: [String] = ["android.permission.INTERNET"],
                                debuggable: Bool? = nil, activities: Int = 2, services: Int = 1, stripNames: Bool = false,
                                utf8: Bool = false) -> Data {
        func attribute(_ name: String, _ id: UInt32, _ value: AXMLValue) -> AXMLAttribute {
            AXMLAttribute(name: name, resourceID: id, value: value, stripName: stripNames)
        }
        var application: [AXMLAttribute] = [attribute("label", 0x0101_0001, .reference(0x7F01_0000))]
        if let debuggable { application.append(attribute("debuggable", 0x0101_000F, .boolean(debuggable))) }
        var children: [AXMLNode] = [
            .element("uses-sdk", [attribute("minSdkVersion", 0x0101_020C, .integer(minSDK)),
                                   attribute("targetSdkVersion", 0x0101_0270, .integer(targetSDK))], [])
        ]
        for permission in permissions {
            children.append(.element("uses-permission", [attribute("name", 0x0101_0003, .string(permission))], []))
        }
        var components: [AXMLNode] = []
        for _ in 0..<activities { components.append(.element("activity", [attribute("name", 0x0101_0003, .string(".Main"))], [])) }
        for _ in 0..<services { components.append(.element("service", [attribute("name", 0x0101_0003, .string(".Work"))], [])) }
        children.append(.element("application", application, components))
        let root = AXMLNode.element("manifest", [
            AXMLAttribute(name: "package", resourceID: nil, value: .string(package)),
            attribute("versionCode", 0x0101_021B, .integer(versionCode)),
            attribute("versionName", 0x0101_021C, .string(versionName))
        ], children)
        return axml(root, utf8: utf8)
    }

    // MARK: Protobuf XML (Android App Bundle manifests)

    enum Proto {
        static func varint(_ value: UInt64) -> Data {
            var rest = value
            var bytes: [UInt8] = []
            repeat {
                var byte = UInt8(rest & 0x7F)
                rest >>= 7
                if rest > 0 { byte |= 0x80 }
                bytes.append(byte)
            } while rest > 0
            return Data(bytes)
        }
        static func field(_ number: Int, _ payload: Data) -> Data { varint(UInt64(number << 3 | 2)) + varint(UInt64(payload.count)) + payload }
        static func string(_ number: Int, _ text: String) -> Data { field(number, Data(text.utf8)) }
        static func number(_ number: Int, _ value: UInt64) -> Data { varint(UInt64(number << 3)) + varint(value) }

        /// An `XmlNode` holding an `XmlElement` with string attributes (the android namespace is implied) and children.
        static func element(_ name: String, _ attributes: [(String, String)] = [], children: [Data] = []) -> Data {
            var body = Data()
            body += field(1, string(1, "android") + string(2, "http://schemas.android.com/apk/res/android"))
            body += string(2, "")
            body += string(3, name)
            for (key, value) in attributes {
                body += field(4, string(1, key == "package" ? "" : "http://schemas.android.com/apk/res/android") + string(2, key) + string(3, value)
                              + number(5, 0x0101_0000) + field(6, string(1, "compiled-item-ignored")))
            }
            for child in children { body += field(5, child) }
            return field(1, body) + field(3, number(1, 7)) // element, then a source position
        }

        static func text(_ value: String) -> Data { string(2, value) }
    }

    static func protoManifest(package: String = "com.example.bundle", versionCode: Int = 77, versionName: String = "9.8.7",
                              minSDK: Int = 23, targetSDK: Int = 35, permissions: [String] = ["android.permission.CAMERA"],
                              debuggable: Bool? = nil, activities: Int = 1, includeTextNodes: Bool = true) -> Data {
        var children: [Data] = [Proto.element("uses-sdk", [("minSdkVersion", "\(minSDK)"), ("targetSdkVersion", "\(targetSDK)")])]
        if includeTextNodes { children.append(Proto.text("\n  ")) }
        children += permissions.map { Proto.element("uses-permission", [("name", $0)]) }
        var application: [(String, String)] = []
        if let debuggable { application.append(("debuggable", debuggable ? "true" : "false")) }
        children.append(Proto.element("application", application, children: (0..<activities).map { _ in Proto.element("activity", [("name", ".Main")]) }))
        return Proto.element("manifest", [("package", package), ("versionCode", "\(versionCode)"), ("versionName", versionName)], children: children)
    }

    // MARK: XAR

    struct XARNode {
        let name: String
        var data: Data?
        var children: [XARNode] = []
        init(_ name: String, data: Data? = nil, children: [XARNode] = []) {
            self.name = name
            self.data = data
            self.children = children
        }
    }

    /// A flat-package container: a zlib-compressed XML table of contents followed by a heap whose members
    /// are zlib-compressed (`application/x-gzip`) or stored (`application/octet-stream`).
    static func xar(_ nodes: [XARNode], signatureCertificates: [Data] = [], stored: Bool = false) -> Data {
        var heap = Data()
        var nextID = 0
        func render(_ node: XARNode) -> String {
            nextID += 1
            let id = nextID
            var xml = "<file id=\"\(id)\"><name>\(node.name)</name>"
            if let data = node.data {
                let packed = stored ? data : zlibCompress(data)
                xml += "<type>file</type><mtime>2026-01-01T00:00:00Z</mtime><data><offset>\(heap.count)</offset><length>\(packed.count)</length><size>\(data.count)</size>"
                xml += "<encoding style=\"\(stored ? "application/octet-stream" : "application/x-gzip")\"/></data>"
                heap += packed
            } else {
                xml += "<type>directory</type>"
            }
            xml += node.children.map(render).joined() + "</file>"
            return xml
        }
        var toc = "<xar><toc>" + nodes.map(render).joined()
        if !signatureCertificates.isEmpty {
            toc += "<signature style=\"RSA\"><offset>0</offset><size>0</size><KeyInfo><X509Data>"
            toc += signatureCertificates.map { "<X509Certificate>\($0.base64EncodedString())</X509Certificate>" }.joined()
            toc += "</X509Data></KeyInfo></signature>"
        }
        toc += "</toc></xar>"
        let tocData = Data(toc.utf8)
        let packedTOC = zlibCompress(tocData)
        return Data("xar!".utf8) + big(28, 2) + big(1, 2) + big(UInt64(packedTOC.count), 8) + big(UInt64(tocData.count), 8)
            + big(0, 4) + packedTOC + heap
    }

    static func distribution(title: String = "Synthetic Installer", minimumOS: String = "11.0",
                             hostArchitectures: String = "x86_64,arm64", references: [(id: String, version: String, kilobytes: Int)]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><installer-gui-script minSpecVersion=\"1\"><title>\(title)</title>"
        xml += "<product id=\"com.example.synthetic.product\" version=\"3.4.5\"/>"
        xml += "<options customize=\"never\" hostArchitectures=\"\(hostArchitectures)\"/>"
        xml += "<volume-check><allowed-os-versions><os-version min=\"\(minimumOS)\"/></allowed-os-versions></volume-check>"
        xml += references.map { "<pkg-ref id=\"\($0.id)\" version=\"\($0.version)\" installKBytes=\"\($0.kilobytes)\"/>" }.joined()
        xml += "</installer-gui-script>"
        return Data(xml.utf8)
    }

    static func packageInfo(identifier: String, version: String = "1.0", installLocation: String = "/Applications",
                            files: Int = 12, kilobytes: Int = 640, scripts: [String] = ["preinstall", "postinstall"]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><pkg-info format-version=\"2\" identifier=\"\(identifier)\" version=\"\(version)\" install-location=\"\(installLocation)\" auth=\"root\">"
        xml += "<payload numberOfFiles=\"\(files)\" installKBytes=\"\(kilobytes)\"/><scripts>"
        xml += scripts.map { "<\($0) file=\"./\($0)\"/>" }.joined()
        xml += "</scripts></pkg-info>"
        return Data(xml.utf8)
    }

    // MARK: UDIF

    static let udifSectorBytes = 512

    /// A UDIF image: a data fork of filler bytes, an XML property list with one block map per partition
    /// and the 512-byte "koly" trailer.
    static func udif(partitions: [(name: String, sectors: Int, runTypes: [UInt32])], flags: UInt64 = 1,
                     sectorsOverride: Int? = nil, includePropertyList: Bool = true) -> Data {
        let dataFork = Data(repeating: 0xAB, count: 2_048)
        var blkx: [[String: Any]] = []
        for (index, partition) in partitions.enumerated() {
            var map = Data("mish".utf8) + big(1, 4) + big(0, 8) + big(UInt64(partition.sectors), 8) + big(0, 8)
            map += big(0, 4) + big(UInt64(index), 4) + Data(repeating: 0, count: 24 + 136)
            map += big(UInt64(partition.runTypes.count), 4)
            for (position, type) in partition.runTypes.enumerated() {
                map += big(UInt64(type), 4) + big(0, 4) + big(UInt64(position), 8) + big(1, 8) + big(0, 8) + big(0, 8)
            }
            blkx.append(["Attributes": "0x0050", "CFName": partition.name, "Data": map, "ID": "\(index)", "Name": partition.name])
        }
        let xml = includePropertyList ? plist(["resource-fork": ["blkx": blkx]]) : Data()
        let xmlOffset = dataFork.count
        let totalSectors = sectorsOverride ?? partitions.reduce(0) { $0 + $1.sectors }
        var trailer = Data("koly".utf8) + big(4, 4) + big(512, 4) + big(flags, 4)
        trailer += big(0, 8) + big(0, 8) + big(UInt64(dataFork.count), 8) + big(0, 8) + big(0, 8)
        trailer += big(1, 4) + big(1, 4) + Data(repeating: 0, count: 16)
        trailer += big(0, 4) + big(0, 4) + Data(repeating: 0, count: 128)
        trailer += big(UInt64(xmlOffset), 8) + big(UInt64(xml.count), 8)
        trailer += Data(repeating: 0, count: 120) + big(0, 4) + big(0, 4) + Data(repeating: 0, count: 128)
        trailer += big(1, 4) + big(UInt64(totalSectors), 8) + Data(repeating: 0, count: 12)
        precondition(trailer.count == 512)
        return dataFork + xml + trailer
    }

    // MARK: Bencode

    indirect enum Bencode {
        case integer(Int)
        case text(String)
        case bytes(Data)
        case list([Bencode])
        case dictionary([(String, Bencode)])

        var encoded: Data {
            switch self {
            case .integer(let value): Data("i\(value)e".utf8)
            case .text(let value): Data("\(value.utf8.count):".utf8) + Data(value.utf8)
            case .bytes(let value): Data("\(value.count):".utf8) + value
            case .list(let values): Data("l".utf8) + values.reduce(Data()) { $0 + $1.encoded } + Data("e".utf8)
            case .dictionary(let pairs):
                Data("d".utf8) + pairs.sorted { $0.0 < $1.0 }.reduce(Data()) { $0 + Bencode.text($1.0).encoded + $1.1.encoded } + Data("e".utf8)
            }
        }
    }

    static func torrent(name: String = "Synthetic Data", files: [(path: [String], length: Int)]? = nil, length: Int = 4_096,
                        pieceLength: Int = 1_024, announce: String? = "udp://tracker.example.test:6969/announce?passkey=\(secret)",
                        announceList: [[String]] = [], isPrivate: Bool = false, comment: String? = "Synthetic comment",
                        createdBy: String? = "Synthetic Tool 1.0", creationDate: Int? = 1_700_000_000,
                        webSeeds: [String] = [], extraInfo: [(String, Bencode)] = []) -> (data: Data, info: Data) {
        // Wrapping sum: a test may declare sizes whose real total overflows, to prove the parser rejects them.
        let total = files?.reduce(0) { $0 &+ $1.length } ?? length
        let pieceCount = total > 0 ? (total - 1) / pieceLength + 1 : 1
        var info: [(String, Bencode)] = [
            ("name", .text(name)), ("piece length", .integer(pieceLength)),
            ("pieces", .bytes(Data(repeating: 0x5A, count: 20 * pieceCount)))
        ]
        if let files {
            info.append(("files", .list(files.map { .dictionary([("length", .integer($0.length)), ("path", .list($0.path.map { .text($0) }))]) })))
        } else {
            info.append(("length", .integer(length)))
        }
        if isPrivate { info.append(("private", .integer(1))) }
        info += extraInfo
        var root: [(String, Bencode)] = [("info", .dictionary(info))]
        if let announce { root.append(("announce", .text(announce))) }
        if !announceList.isEmpty { root.append(("announce-list", .list(announceList.map { .list($0.map { .text($0) }) }))) }
        if let comment { root.append(("comment", .text(comment))) }
        if let createdBy { root.append(("created by", .text(createdBy))) }
        if let creationDate { root.append(("creation date", .integer(creationDate))) }
        if !webSeeds.isEmpty { root.append(("url-list", .list(webSeeds.map { .text($0) }))) }
        return (Bencode.dictionary(root).encoded, Bencode.dictionary(info).encoded)
    }
}
