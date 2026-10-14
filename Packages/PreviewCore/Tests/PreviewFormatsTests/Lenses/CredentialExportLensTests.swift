import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func request(_ format: FormatID, fileName: String = "export") -> PreviewLensRequest {
    PreviewLensRequest(formatID: format, fileName: fileName)
}

private func findings(_ text: String, format: FormatID) throws -> [PreviewFinding] {
    try CredentialExportLens().findings(in: text, request: request(format), context: RequestContext(budget: .standard))
}

private func finding(_ kind: PreviewFindingKind, in findings: [PreviewFinding]) -> PreviewFinding? {
    findings.first { $0.kind == kind }
}

/// One-based lines of the text that contain `needle`, by plain line feeds.
private func lines(containing needle: String, in text: String) -> [Int] {
    text.components(separatedBy: "\n").enumerated().filter { $0.element.contains(needle) }.map { $0.offset + 1 }
}

/// The headers of the password managers' own CSV exports (sources: each product's exporter or the importer
/// fixtures of Bitwarden and Proton; Keeper writes no header row, so no header can be listed for it).
/// Every one must be recognized by the general rule, which is the only recognition the lens has.
private let knownHeaders: [(manager: String, header: String)] = [
    ("Bitwarden", "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp"),
    ("Bitwarden organization", "collections,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp"),
    ("1Password 8", "Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes"),
    ("1Password 7 for Windows, leading columns", "\"UUID\",\"TITLE\",\"USERNAME\",\"PASSWORD\",\"URL\",\"URLS\",\"EMAIL\",\"MASTER-PASSWORD\",\"NOTES\""),
    ("Apple Passwords and Safari", "Title,URL,Username,Password,Notes,OTPAuth"),
    ("Safari before macOS 15", "Title,Url,Username,Password"),
    ("Chrome, Edge and Brave", "name,url,username,password,note"),
    ("Chrome before notes", "name,url,username,password"),
    ("Firefox", "\"url\",\"username\",\"password\",\"httpRealm\",\"formActionOrigin\",\"guid\",\"timeCreated\",\"timeLastUsed\",\"timePasswordChanged\""),
    ("LastPass", "url,username,password,totp,extra,name,grouping,fav"),
    ("LastPass before totp", "url,username,password,extra,name,grouping,fav"),
    ("Dashlane", "username,username2,username3,title,password,note,url,category,otpSecret"),
    ("Dashlane with otpauth links", "username,username2,username3,title,password,note,url,category,otpUrl"),
    ("Proton Pass", "type,name,url,autofillUrls,email,username,password,note,totp,createTime,modifyTime,vault"),
    ("Proton Pass 2024", "type,name,url,email,username,password,note,totp,createTime,modifyTime,vault"),
    ("Proton Pass before email", "type,name,url,username,password,note,totp,createTime,modifyTime,vault"),
    ("KeePassXC", "\"Group\",\"Title\",\"Username\",\"Password\",\"URL\",\"Notes\",\"TOTP\",\"Icon\",\"Last Modified\",\"Created\""),
    ("KeePassXC before totp", "\"Group\",\"Title\",\"Username\",\"Password\",\"URL\",\"Notes\""),
    ("NordPass", "name,url,additional_urls,username,password,note,cardholdername,cardnumber,cvc,expirydate,zipcode,folder,full_name,phone_number,email,address1,address2,city,country,state,type,custom_fields"),
    ("NordPass before additional urls", "name,url,username,password,note,cardholdername,cardnumber,cvc,expirydate,zipcode,folder,full_name,phone_number,email,address1,address2,city,country,state,type,custom_fields"),
    ("Keeper with a header added by hand", "Folder,Title,Login,Password,Website Address,Notes,Shared Folder,Custom Fields")
]

@Suite("Credential export lens: CSV and TSV")
struct CredentialExportDelimitedTests {
    @Test(arguments: knownHeaders.map(\.header))
    func everyKnownManagerHeaderIsRecognized(header: String) throws {
        let columns = header.split(separator: ",").count
        let row = (1...columns).map { "synthetic\($0)" }.joined(separator: ",")
        let result = try findings("\(header)\n\(row)\n\(row)\n", format: .csv)
        let export = try #require(finding(.exportReadableLogins, in: result), "\(header)")
        #expect((export.count, export.lines) == (2, [1]))
        #expect(export.detail == PreviewFindingDetail.none)
        #expect(result.count == 1)
    }

    @Test func countsRecordsNotLinesAndSkipsEmptyOnes() throws {
        let text = """
        name,url,username,password,note
        one,https://one.invalid,a,••••,"first line
        second line

        fourth line"
        ,,,,

        two,https://two.invalid,b,••••,
        "",,,,
        """
        let export = try #require(finding(.exportReadableLogins, in: try findings(text, format: .csv)))
        #expect((export.count, export.lines) == (2, [1]))
    }

    @Test func aHeaderWithoutRecordsReportsNothing() throws {
        #expect(try findings("name,url,username,password,note\n", format: .csv).isEmpty)
        #expect(try findings("name,url,username,password,note", format: .csv).isEmpty)
        #expect(try findings("name,url,username,password,note\n,,,,\n\n", format: .csv).isEmpty)
    }

    @Test func tabSeparatedExportsAreRecognizedToo() throws {
        let text = "Title\tURL\tUsername\tPassword\nsite\thttps://x.invalid\tme\t••••\n"
        #expect(finding(.exportReadableLogins, in: try findings(text, format: .tsv))?.count == 1)
        // The same text read with the wrong delimiter is one column and says nothing.
        #expect(try findings(text, format: .csv).isEmpty)
    }

    @Test(arguments: [
        "Web Site,Login Name,Password\nx,y,z\n",
        "SITE,E-Mail,PWD\nx,y,z\n",
        "login_url,login,login_password,extra\nx,y,z,w\n",
        "\u{FEFF}url,email,passwd\nx,y,z\n",
        "\"URI\",\"User\",\"Password\"\n\"x\",\"y\",\"z\"\n",
        "website_address,user_id,password\nx,y,z\n"
    ])
    func aPasswordUsernameAndAddressColumnTogetherAreAnExport(text: String) throws {
        #expect(finding(.exportReadableLogins, in: try findings(text, format: .csv))?.count == 1)
    }

    @Test(arguments: [
        "id,name,email,city\n1,a,b,c\n",
        "username,password\nme,••••\n",
        "url,password\nx,y\n",
        "url,username\nx,y\n",
        "email,password,age\na,b,3\n",
        "password_hint,username,url\nx,y,z\n",
        "user,passed,url\nme,yes,x\n",
        "date,visitor,page,referrer\n2026-01-01,a,/,/\n",
        "Name,Phone,Address\nA,1,2\n",
        "a\nb\nc\n",
        ""
    ])
    func ordinaryTablesStaySilent(text: String) throws {
        #expect(try findings(text, format: .csv).isEmpty)
    }

    @Test func aPasswordColumnMustBeCompleteNotPartOfAnotherName() throws {
        #expect(try findings("url,username,passwordless\nx,y,z\n", format: .csv).isEmpty)
        #expect(try findings("url,username,password_strength\nx,y,z\n", format: .csv).isEmpty)
    }

    @Test func malformedTextProducesNothingAndDoesNotThrow() throws {
        #expect(try findings("name,url,username,password\n\"unterminated,x,y,z\n", format: .csv).isEmpty)
        #expect(try findings("name,url,username,password\nab\"c,x,y,z\n", format: .csv).isEmpty)
        #expect(try findings("name,url,username,password\n\"ab\"c,x,y,z\n", format: .csv).isEmpty)
    }

    @Test func otherFormatsAreIgnored() throws {
        #expect(try findings("name,url,username,password\na,b,c,d\n", format: .markdown).isEmpty)
    }

    @Test func cancellationStopsAnActiveRead() async throws {
        var text = "name,url,username,password,note\n"
        for index in 0..<400 { text += "site\(index),https://example.invalid/\(index),user\(index),••••,\"a note\nover two lines\"\n" }
        let source = text
        let completed = try await CancellationTest.expectStopsActiveParse(budget: .standard) { context in
            let result = try CredentialExportLens().findings(in: source, request: request(.csv), context: context)
            return ParsedTextDocument(text: "\(result.first?.count ?? 0)")
        }
        #expect(completed.text == "400")
    }
}

@Suite("Credential export lens: JSON")
struct CredentialExportJSONTests {
    private let token = SecretFieldPolicy.concealmentToken

    private func bitwarden(encrypted: String = "false") -> String {
        """
        {
          "encrypted" : \(encrypted),
          "folders" : [],
          "items" : [
            {
              "id" : "1",
              "login" : {
                "password" : \(token),
                "totp" : \(token),
                "uris" : [
                  { "uri" : "https:\\/\\/one.invalid" }
                ],
                "username" : "synthetic-one"
              },
              "name" : "one",
              "type" : 1
            },
            {
              "id" : "2",
              "login" : null,
              "name" : "a note",
              "secureNote" : { "type" : 0 },
              "type" : 2
            },
            {
              "id" : "3",
              "login" : {
                "password" : \(token),
                "username" : "synthetic-two"
              },
              "name" : "two",
              "type" : 1
            }
          ]
        }
        """
    }

    @Test func anUnencryptedBitwardenExportReportsItsLoginsAtTheirLines() throws {
        let text = bitwarden()
        let export = try #require(finding(.exportReadableLogins, in: try findings(text, format: .json)))
        #expect(export.count == 2)
        #expect(export.lines == lines(containing: "\"login\" : {", in: text))
        #expect(export.lines == [7, 27])
        #expect(finding(.exportReadableCodeSecrets, in: try findings(text, format: .json)) == nil)
    }

    @Test func encryptedOrAmbiguousBitwardenExportsStaySilent() throws {
        #expect(try findings(bitwarden(encrypted: "true"), format: .json).isEmpty)
        #expect(try findings(bitwarden(encrypted: "\"false\""), format: .json).isEmpty)
        #expect(try findings(bitwarden(encrypted: "null"), format: .json).isEmpty)
        let missing = bitwarden().replacingOccurrences(of: "\"encrypted\" : false,", with: "")
        #expect(try findings(missing, format: .json).isEmpty)
        let protected = #"{ "encrypted" : true, "passwordProtected" : true, "salt" : "c3ludGhldGlj", "data" : "2.c3ludGhldGlj|c3ludGhldGlj" }"#
        #expect(try findings(protected, format: .json).isEmpty)
        #expect(try findings(#"{ "encrypted" : false, "folders" : [], "items" : [] }"#, format: .json).isEmpty)
        #expect(try findings(#"{ "encrypted" : false, "items" : [ { "login" : {} }, { "login" : null } ] }"#, format: .json).isEmpty)
    }

    private func aegis(slots: String = "null", db: String? = nil) -> String {
        let database = db ?? """
        {
            "entries" : [
              {
                "info" : {
                  "algo" : "SHA1",
                  "digits" : 6,
                  "secret" : \(token)
                },
                "issuer" : "One",
                "name" : "a",
                "type" : "totp"
              },
              {
                "info" : {
                  "secret" : \(token)
                },
                "name" : "b",
                "type" : "totp"
              },
              {
                "name" : "no secret",
                "type" : "totp"
              }
            ],
            "version" : 3
          }
        """
        return """
        {
          "db" : \(database),
          "header" : {
            "params" : null,
            "slots" : \(slots)
          },
          "version" : 1
        }
        """
    }

    @Test func anUnencryptedAegisExportReportsEachSecret() throws {
        let text = aegis()
        let export = try #require(finding(.exportReadableCodeSecrets, in: try findings(text, format: .json)))
        #expect(export.count == 2)
        #expect(export.lines == lines(containing: "\"secret\" :", in: text))
        #expect(finding(.exportReadableLogins, in: try findings(text, format: .json)) == nil)
    }

    @Test func encryptedAegisExportsStaySilent() throws {
        #expect(try findings(aegis(slots: "[ { \"type\" : 1, \"uuid\" : \"x\" } ]"), format: .json).isEmpty)
        #expect(try findings(aegis(db: "\"c3ludGhldGljYmxvYg==\""), format: .json).isEmpty)
        #expect(try findings(aegis(slots: "[]"), format: .json).isEmpty)
        let noSlots = aegis().replacingOccurrences(of: "\"slots\" : null", with: "\"other\" : null")
        #expect(try findings(noSlots, format: .json).isEmpty)
    }

    @Test func aTwoFASExportReportsEachService() throws {
        let text = """
        {
          "appOrigin" : "ios",
          "schemaVersion" : 4,
          "services" : [
            { "name" : "One", "otp" : { "account" : "a" }, "secret" : \(token) },
            { "name" : "Two",
              "secret" : \(token) },
            { "name" : "No secret" }
          ]
        }
        """
        let export = try #require(finding(.exportReadableCodeSecrets, in: try findings(text, format: .json)))
        #expect((export.count, export.lines) == (2, [5, 7]))
    }

    @Test func encryptedOrUnrelatedTwoFASShapesStaySilent() throws {
        #expect(try findings(#"{ "schemaVersion" : 4, "services" : [], "servicesEncrypted" : "c3ludGhldGlj", "reference" : "x" }"#, format: .json).isEmpty)
        #expect(try findings(#"{ "schemaVersion" : 4, "services" : [ { "secret" : "x" } ], "servicesEncrypted" : "c3ludGhldGlj" }"#, format: .json).isEmpty)
        #expect(try findings(#"{ "services" : [ { "secret" : "x" } ] }"#, format: .json).isEmpty)
        #expect(try findings(#"{ "schemaVersion" : 4, "services" : [ { "name" : "x" } ] }"#, format: .json).isEmpty)
        #expect(try findings(#"{ "schemaVersion" : 4, "services" : {} }"#, format: .json).isEmpty)
    }

    @Test func anAndOTPExportReportsEachEntryWithAKnownType() throws {
        let text = """
        [
          { "secret" : \(token), "issuer" : "One", "type" : "TOTP", "period" : 30 },
          { "secret" : \(token), "type" : "HOTP", "counter" : 1 },
          {
            "secret" : \(token),
            "type" : "STEAM"
          },
          { "secret" : \(token), "type" : "OTHER" },
          { "type" : "TOTP" },
          { "secret" : \(token) },
          5
        ]
        """
        let export = try #require(finding(.exportReadableCodeSecrets, in: try findings(text, format: .json)))
        #expect((export.count, export.lines) == (3, [2, 3, 5]))
    }

    @Test(arguments: [
        "[]", "{}", "[1, 2, 3]", "[{ \"type\" : \"TOTP\" }]", "[{ \"secret\" : \"x\", \"type\" : 3 }]", "null", "\"x\"",
        #"{ "items" : [ { "login" : { "username" : "a" } } ] }"#,
        #"{ "name" : "package", "version" : "1.0.0", "scripts" : { "build" : "make" } }"#
    ])
    func ordinaryJSONStaysSilent(text: String) throws {
        #expect(try findings(text, format: .json).isEmpty)
    }

    @Test func toleratesCommentsAndTrailingCommas() throws {
        let text = """
        // synthetic
        {
          "encrypted": false, /* plain */
          "items": [
            { "login": { "username": "a", "password": \(token), }, },
          ],
        }
        """
        #expect(finding(.exportReadableLogins, in: try findings(text, format: .json))?.lines == [5])
    }

    @Test(arguments: ["{", "{ \"encrypted\": false, \"items\": [ { \"login\": { \"username\": } } ] }", "[ { \"secret\": \"x\", \"type\": \"TOTP\" ", "tru"])
    func malformedJSONProducesNothingAndDoesNotThrow(text: String) throws {
        #expect(try findings(text, format: .json).isEmpty)
    }

    @Test func cancellationStopsAnActiveRead() async throws {
        var text = "[\n"
        for index in 0..<400 { text += "  { \"secret\" : \(token), \"issuer\" : \"issuer\(index)\", \"type\" : \"TOTP\" },\n" }
        text += "  { \"secret\" : \(token), \"type\" : \"HOTP\" }\n]\n"
        let source = text
        let completed = try await CancellationTest.expectStopsActiveParse(budget: .standard) { context in
            let result = try CredentialExportLens().findings(in: source, request: request(.json), context: context)
            return ParsedTextDocument(text: "\(result.first?.count ?? 0)")
        }
        #expect(completed.text == "401")
    }
}
