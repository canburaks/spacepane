import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// Clocks and certificates for the validity-findings tests. Every test sets its own clock from `now`;
/// none reads the real date, and a validity end is always stated as an offset from that clock.
enum ExpiryFixtures {
    /// 2027-01-15T08:00:00Z, the package tests' fixed clock.
    static let now = PackageTestSupport.now
    static let day: TimeInterval = 86_400

    /// A far-away start, so a certificate is already valid at `now` unless a test says otherwise.
    static let longAgo = -3_650 * day

    // MARK: Time

    /// ASN.1 UTCTime text for a date. The tests stay well inside 1950...2049, the range UTCTime can state.
    static func utcTime(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%02d%02d%02d%02d%02d%02dZ", (parts.year ?? 0) % 100, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// The clock moved by `seconds`.
    static func after(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    // MARK: Endings

    /// Where a validity end stands against the clock, as the findings must report it.
    enum Standing: Equatable, Sendable {
        case valid, endsSoon(days: Int), expired
    }

    /// A validity end `seconds` after the clock and the standing it must be given. Shared by the
    /// certificate and profile tests so both honour one table.
    struct Ending: Sendable, CustomTestStringConvertible {
        let seconds: TimeInterval
        let standing: Standing
        var testDescription: String { "ends \(seconds) s after the clock" }
    }

    static let endings: [Ending] = [
        Ending(seconds: 29.2 * day, standing: .endsSoon(days: 30)),
        Ending(seconds: 30 * day, standing: .endsSoon(days: 30)),
        Ending(seconds: 30 * day + 1, standing: .valid),
        Ending(seconds: 31 * day, standing: .valid),
        Ending(seconds: 10 * day, standing: .endsSoon(days: 10)),
        Ending(seconds: 9 * day + 1, standing: .endsSoon(days: 10)),
        Ending(seconds: 9 * day, standing: .endsSoon(days: 9)),
        Ending(seconds: day + 1, standing: .endsSoon(days: 2)),
        Ending(seconds: day, standing: .endsSoon(days: 1)),
        Ending(seconds: 1, standing: .endsSoon(days: 1)),
        // The last second of validity is still valid, and a part of a day counts as a day.
        Ending(seconds: 0, standing: .endsSoon(days: 1)),
        Ending(seconds: -1, standing: .expired),
        Ending(seconds: -400 * day, standing: .expired)
    ]

    // MARK: Certificates

    /// A P-256 certificate whose validity runs from `start` to `end` seconds relative to `now`.
    static func ecCertificate(start: TimeInterval = longAgo, end: TimeInterval, commonName: String = "ec.example.test",
                              serial: Int = 0x1234_5678) -> Data {
        PackageFixtures.certificate(commonName: commonName, notBefore: utcTime(after(start)), notAfter: utcTime(after(end)),
                                    serial: serial)
    }

    /// An RSA certificate with a modulus of exactly `bits` bits (a multiple of eight). The modulus is
    /// a patterned number, not a product of primes, and the signature is filler: Security parses the
    /// structure and reports the key size without verifying either, and nothing here is ever trusted.
    static func rsaCertificate(bits: Int, start: TimeInterval = longAgo, end: TimeInterval,
                               commonName: String = "rsa.example.test", serial: Int = 0x2468) -> Data {
        typealias DER = PackageFixtures.DER
        let null = DER.tlv(0x05, Data())
        let signatureAlgorithm = DER.sequence([DER.oid("1.2.840.113549.1.1.11"), null])
        let subject = DER.name([("2.5.4.3", commonName)])
        var modulus = Data((0..<bits / 8).map { UInt8(truncatingIfNeeded: $0 &* 73 &+ 41) })
        modulus[0] = 0xC0 | (modulus[0] & 0x3F)
        modulus[modulus.count - 1] |= 1
        let publicKey = DER.sequence([DER.tlv(0x02, Data([0]) + modulus), DER.integer(65_537)])
        let keyInfo = DER.sequence([DER.sequence([DER.oid("1.2.840.113549.1.1.1"), null]), DER.bitString(publicKey)])
        let validity = DER.sequence([DER.utcTime(utcTime(after(start))), DER.utcTime(utcTime(after(end)))])
        let tbs = DER.sequence([DER.explicit(0, DER.integer(2)), DER.integer(serial), signatureAlgorithm, subject,
                                validity, subject, keyInfo])
        return DER.sequence([tbs, signatureAlgorithm, DER.bitString(Data(repeating: 0x5A, count: bits / 8))])
    }

    /// Several certificates as one PEM bundle.
    static func bundle(_ certificates: [Data]) -> FileBytes {
        FileBytes(data: Data(certificates.map { PackageFixtures.pem(label: "CERTIFICATE", body: $0) }.joined().utf8))
    }

    // MARK: OpenSSL certificates

    /// Self-signed RSA-1024 certificate made with
    /// `openssl req -x509 -newkey rsa:1024 -nodes -days 3650 -subj "/CN=SpacePane synthetic test" -outform DER`.
    /// Valid 2026-10-14 to 2036-10-11. The private key was written to /dev/null and does not exist.
    static let opensslRSA1024 = Data(base64Encoded: """
        MIICIjCCAYugAwIBAgIUIMBbtFyAetH+DcB3onGwrscH4yIwDQYJKoZIhvcNAQELBQAwIzEhMB8G\
        A1UEAwwYU3BhY2VQYW5lIHN5bnRoZXRpYyB0ZXN0MB4XDTI2MTAxNDA4MDk1MloXDTM2MTAxMTA4\
        MDk1MlowIzEhMB8GA1UEAwwYU3BhY2VQYW5lIHN5bnRoZXRpYyB0ZXN0MIGfMA0GCSqGSIb3DQEB\
        AQUAA4GNADCBiQKBgQC8rzYeqdaZPZmeThyTyJd906if8+AxPMEodiD+cKbwN3Bjcw6ZTychAx49\
        j5ZludsJMENE3h8w1NzlYK7ZnrCa2B7V1tbxfKGuqq7drBVwSAqzXLWdG8z8uduRPOT3xGC+mpHv\
        fOTCDKg0H/a8/UmEVjcjMRpzl7Y/cJTZS4PRNQIDAQABo1MwUTAdBgNVHQ4EFgQU7WxwwPixT5A1\
        zMwtXIn01POXKRowHwYDVR0jBBgwFoAU7WxwwPixT5A1zMwtXIn01POXKRowDwYDVR0TAQH/BAUw\
        AwEB/zANBgkqhkiG9w0BAQsFAAOBgQCZsZQQ8jMyJlidCm2MQQBQvzHmzCK3QADFfTofb90D4T+S\
        DSXjDxHHVd4jXNw6XYiIrdt/CEiYQ5x53eyR2Dg9Q3YNooHebWYT6uoTJ1hWJKmiJGepWBWeB4qX\
        y0rH/q1lXGWL9XQNG5kV3/OJ7vYd42TR7xX8VyQcnss3ySvUqw==
        """)!

    /// The same command with `rsa:2048`. Valid 2026-10-14 to 2036-10-11; its private key does not exist either.
    static let opensslRSA2048 = Data(base64Encoded: """
        MIIDJzCCAg+gAwIBAgIUV1vdKuzzhaMWJrYjwl/w+DFzPv8wDQYJKoZIhvcNAQELBQAwIzEhMB8G\
        A1UEAwwYU3BhY2VQYW5lIHN5bnRoZXRpYyB0ZXN0MB4XDTI2MTAxNDA4MDk1MloXDTM2MTAxMTA4\
        MDk1MlowIzEhMB8GA1UEAwwYU3BhY2VQYW5lIHN5bnRoZXRpYyB0ZXN0MIIBIjANBgkqhkiG9w0B\
        AQEFAAOCAQ8AMIIBCgKCAQEAikrbehxwK0u5Y5OR1UTqDamJNLp1k3qS0bJkxSxfctSLwLQa8vrQ\
        JuPIkwYcr2DbHgO74fQZylkR6bBpoODnEbaIvcD9jKKUfsLpAMK99AonPQwVqJiiFuwvQ/QCoanf\
        uoFGRgT29myDoihnOnZ5++OOqF7B7sxvzvlLb3jrMruoZ+ndCzHA28GAhmpwLzdZXxBnkrMDS8ta\
        usKj2432VesfZSyeYyUOPLtXvbKNhLCImPkE2tVgPDOODdM32JXRZsh/gkoYolZ2xopuXkQjxpWx\
        2ITMIuFwBGuD8XNWBP0WNELH34O33rzT2c9CMC7EodFpBPjzZISRdRJUq48rJwIDAQABo1MwUTAd\
        BgNVHQ4EFgQUd1vwkRAIySpKD2zFTx4kFcZ33QMwHwYDVR0jBBgwFoAUd1vwkRAIySpKD2zFTx4k\
        FcZ33QMwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAW+OcdTSB5w7t2uTAc70h\
        E9kqIeVRxl10fvFPChpsIez/RnuW0czouEd5MZsJ78/grBN3R9fY08M7GyHJhqTITf1RNP/sz5u5\
        yOIONv5YhMbaYLsnbiVOwuCvkhJWQngbi1Go6L/id97DcqdmxQmDRcOXHbZOPyqq8YCePY/K/7w7\
        /NO70lxlo8y+OZspqyPGBqERx3Fw/EoRS0sgxFS4jSHbWQ636yA5fnPZBGzeX0/yMTrtj/1QOAMY\
        ePbQEk/zn1d6nWExlbDi8rRzyl6+7lYqpmkXz2gtGx1L19WveqHr8UglDKLflvmB3LEqhAezS8Hn\
        TRZkY8gI5aDIXMUNqA==
        """)!

    /// A clock inside the OpenSSL certificates' validity.
    static let opensslClock = Date(timeIntervalSince1970: 1_893_456_000) // 2030-01-01T00:00:00Z
}
