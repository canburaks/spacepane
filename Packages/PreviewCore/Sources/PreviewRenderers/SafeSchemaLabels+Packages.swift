import Foundation
import PreviewContracts

/// Summary schemas written by the package, certificate, disk-image and torrent adapters. Only the
/// app-owned field names listed here are translated. Names, paths, identifiers, entitlement keys,
/// permission names, partition names, hashes and every other document value stay exactly as stored.
extension SummaryLabelSet {
    static let packages = SummaryLabelSet(
        formats: [.applicationBundle, .iosApp, .androidApp, .provisioningProfile, .certificate,
                  .installerPackage, .diskImage, .torrent],
        fields: { parent in
            switch parent {
            case []:
                return ["name", "displayName", "bundleIdentifier", "version", "build", "minimumOSVersion", "category",
                        "executable", "platforms", "deviceFamilies", "documentTypes", "urlSchemes", "usageDescriptions",
                        "architectures", "executableKind", "signature", "bundleSize", "bundleItems", "partial",
                        "provisioning", "archiveFormat", "listedEntries", "entries",
                        "packageName", "applicationLabel", "versionCode", "versionName", "minSdkVersion",
                        "targetSdkVersion", "compileSdkVersion", "debuggable", "activities", "services", "receivers",
                        "providers", "permissionCount", "permissions",
                        "uuid", "appIDName", "teamName", "teamIdentifier", "profileType", "creationDate",
                        "expirationDate", "expired", "entitlements", "provisionedDevices", "provisionsAllDevices",
                        "certificateCount", "certificates", "signatureVerified",
                        "encoding", "unreadableCertificates", "privateKeys", "privateKeyKinds", "otherBlocks",
                        "title", "hostArchitectures", "packages", "signed", "signers",
                        "udifVersion", "imageBytes", "sectorCount", "dataForkBytes", "segmentCount", "internetEnabled",
                        "partitions", "compressions",
                        "layout", "fileCount", "totalBytes", "pieceLength", "pieceCount", "private", "created",
                        "createdBy", "comment", "infoHash", "infoHashV2", "trackers", "webSeeds"]
            case ["signature"]:
                return ["status", "signingIdentifier", "teamIdentifier", "signers", "hardenedRuntime", "appSandbox",
                        "entitlements", "signatureVerified", "notarizationChecked"]
            case ["provisioning"]:
                return ["name", "uuid", "appIDName", "teamName", "teamIdentifier", "platforms", "profileType",
                        "creationDate", "expirationDate", "expired", "entitlements", "provisionedDevices",
                        "provisionsAllDevices", "certificateCount", "certificates", "signatureVerified"]
            case ["entries", "[]"]: return ["path", "type", "bytes", "modified"]
            case ["packages", "[]"]: return ["identifier", "version", "installLocation", "installKilobytes", "payloadFiles", "scripts"]
            case ["partitions", "[]"]: return ["name", "bytes"]
            case ["certificates", "[]"]:
                return ["subject", "issuer", "serialNumber", "notBefore", "notAfter", "expired", "publicKeyAlgorithm",
                        "publicKeyBits", "subjectAlternativeNames", "sha256", "sha1"]
            default: return nil
            }
        },
        keys: [
            "name": .summaryName, "path": .summaryPath, "type": .summaryType, "bytes": .summaryBytes,
            "partial": .summaryPartial, "entries": .summaryEntries, "listedEntries": .summaryListedEntries,
            "signatureVerified": .summarySignatureVerified,
            "displayName": .packageDisplayName, "bundleIdentifier": .packageBundleIdentifier, "version": .packageVersion,
            "build": .packageBuild, "minimumOSVersion": .packageMinimumOSVersion, "category": .packageCategory,
            "executable": .packageExecutable, "platforms": .packagePlatforms, "deviceFamilies": .packageDeviceFamilies,
            "documentTypes": .packageDocumentTypes, "urlSchemes": .packageURLSchemes,
            "usageDescriptions": .packageUsageDescriptions, "architectures": .packageArchitectures,
            "executableKind": .packageExecutableKind, "signature": .packageSignature, "status": .packageStatus,
            "signingIdentifier": .packageSigningIdentifier, "teamIdentifier": .packageTeamIdentifier,
            "signers": .packageSigners, "hardenedRuntime": .packageHardenedRuntime, "appSandbox": .packageAppSandbox,
            "entitlements": .packageEntitlements, "notarizationChecked": .packageNotarizationChecked,
            "bundleSize": .packageBundleSize, "bundleItems": .packageBundleItems, "provisioning": .packageProvisioning,
            "archiveFormat": .packageContainerFormat, "modified": .packageModified,
            "packageName": .packagePackageName, "applicationLabel": .packageApplicationLabel,
            "versionCode": .packageVersionCode, "versionName": .packageVersionName, "minSdkVersion": .packageMinSDK,
            "targetSdkVersion": .packageTargetSDK, "compileSdkVersion": .packageCompileSDK,
            "debuggable": .packageDebuggable, "activities": .packageActivities, "services": .packageServices,
            "receivers": .packageReceivers, "providers": .packageProviders, "permissionCount": .packagePermissionCount,
            "permissions": .packagePermissions,
            "uuid": .packageUUID, "appIDName": .packageAppIDName, "teamName": .packageTeamName,
            "profileType": .packageProfileType, "creationDate": .packageCreated, "created": .packageCreated,
            "expirationDate": .packageExpires, "expired": .packageExpired,
            "provisionedDevices": .packageProvisionedDevices, "provisionsAllDevices": .packageProvisionsAllDevices,
            "certificateCount": .packageCertificateCount, "certificates": .packageCertificates,
            "encoding": .packageEncoding, "unreadableCertificates": .packageUnreadableCertificates,
            "privateKeys": .packagePrivateKeys, "privateKeyKinds": .packagePrivateKeyKinds, "otherBlocks": .packageOtherBlocks,
            "subject": .packageSubject, "issuer": .packageIssuer, "serialNumber": .packageSerialNumber,
            "notBefore": .packageNotBefore, "notAfter": .packageNotAfter,
            "publicKeyAlgorithm": .packagePublicKeyAlgorithm, "publicKeyBits": .packagePublicKeyBits,
            "subjectAlternativeNames": .packageAlternativeNames, "sha256": .packageSHA256, "sha1": .packageSHA1,
            "title": .packageTitle, "hostArchitectures": .packageHostArchitectures, "packages": .packagePackages,
            "signed": .packageStatusSigned, "identifier": .packageIdentifier, "installLocation": .packageInstallLocation,
            "installKilobytes": .packageInstallKilobytes, "payloadFiles": .packagePayloadFiles, "scripts": .packageScripts,
            "udifVersion": .packageUDIFVersion, "imageBytes": .packageImageBytes, "sectorCount": .packageSectorCount,
            "dataForkBytes": .packageDataForkBytes, "segmentCount": .packageSegmentCount,
            "internetEnabled": .packageInternetEnabled, "partitions": .packagePartitions,
            "compressions": .packageCompressions,
            "layout": .packageLayout, "fileCount": .packageFileCount, "totalBytes": .packageTotalBytes,
            "pieceLength": .packagePieceLength, "pieceCount": .packagePieceCount, "private": .packagePrivateTorrent,
            "createdBy": .packageCreatedBy, "comment": .packageComment, "infoHash": .packageInfoHash,
            "infoHashV2": .packageInfoHashV2, "trackers": .packageTrackers, "webSeeds": .packageWebSeeds
        ],
        verbatimFields: ["name", "path", "displayName", "bundleIdentifier", "version", "build", "category", "executable",
                         "identifier", "signingIdentifier", "teamIdentifier", "packageName", "versionName", "title",
                         "subject", "issuer", "comment", "createdBy"],
        booleanFields: ["partial", "signatureVerified", "notarizationChecked", "hardenedRuntime", "appSandbox",
                        "debuggable", "expired", "provisionsAllDevices", "internetEnabled", "private", "signed"],
        countFields: ["listedEntries", "bytes", "bundleSize", "bundleItems", "documentTypes", "urlSchemes", "activities",
                      "services", "receivers", "providers", "permissionCount", "provisionedDevices", "certificateCount",
                      "unreadableCertificates", "privateKeys", "otherBlocks", "payloadFiles", "installKilobytes",
                      "imageBytes", "sectorCount", "dataForkBytes", "segmentCount", "fileCount", "totalBytes",
                      "pieceLength", "pieceCount", "publicKeyBits"],
        valueLabels: [
            "status": ["signed": .packageStatusSigned, "adHoc": .packageStatusAdHoc,
                       "unsigned": .packageStatusUnsigned, "unavailable": .packageStatusUnavailable],
            "executableKind": ["thin": .packageKindThin, "universal": .packageKindUniversal],
            "profileType": ["development": .packageProfileDevelopment, "adHoc": .packageProfileAdHoc,
                            "enterprise": .packageProfileEnterprise, "distribution": .packageProfileDistribution],
            "layout": ["singleFile": .packageLayoutSingle, "multipleFiles": .packageLayoutMultiple],
            "type": entryKinds
        ])
}
