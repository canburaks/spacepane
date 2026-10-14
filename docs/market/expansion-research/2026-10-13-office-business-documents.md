# Office, legal, finance, public-sector and localisation documents: expansion candidates

Researched 2026-10-13 (Europe/Istanbul). One of 11 parallel research angles for the post-CAD expansion. Builds on [the competitor landscape](../2026-10-05-competitor-landscape.md) and [the Safety Lens opportunities](../2026-10-05-unique-feature-opportunities.md). Proposals only: nothing here is a plan commitment or a decision record.

## 1. Method and limits

**Evidence labels.** Every non-obvious claim carries one of these:

- **[V] verified**: I opened the source, or ran the check on this Mac (macOS 27.2, build 26B5101f, Darwin 27.2) during this research.
- **[R] reported**: taken from a web-search result summary of the cited page. The page itself could not be opened from here (HTTP 403/404/503 or DNS failure) or I saw only the snippet. Likely right, but re-check before quoting publicly.
- **[VC] vendor claim**: from the vendor's own App Store text or site.
- **[I] inference**: my reasoning, not a sourced fact.

**What I did.**

- Native status: `pluginkit -mAv -p com.apple.quicklook.preview`, `qlmanage -m plugins`, `mdls -name kMDItemContentType` on empty sample files (a `dyn.*` result means the system declares no content type for that suffix), `qlmanage -t` on tiny hand-made samples, and the `Info.plist` of Apple's own Quick Look extensions.
- Competitors: the iTunes Search API (US storefront). I ran 32 search terms; the first 25 returned results, and the remaining 7 plus every retry got HTTP 403/429 (the lookup endpoint kept working). OFX/QFX, EMF/WMF, EPS, ENEX, Scrivener, MPP, PST, HL7 and EDIFACT were therefore **not** searched through the API. I covered PST, EPS, mbox, OFX/camt and XLIFF with ordinary web searches instead (weaker evidence).
- Mandates: web searches, plus fetches where a site allowed them. The European Commission VAT page and the Gov.pl KSeF page opened; economie.gouv.fr (403), ksef.podatki.gov.pl (DNS), the BMF letter page (503), impots.gouv.fr (404) and Apple's open-source CMS header (404) did not, so those dates are [R].
- The Hancom HWP 5.0 specification: downloaded the PDF and read the copyright page and sections 3.2.6/3.2.7 with PDFKit [V].

**Limits.**

- This Mac has third-party apps installed that declare some types (Evernote, TablePro, Peek and others, plus a SpacePane development build). Only system declarations count as "native"; macOS 15 and 26 may differ from 27.2, especially for OFD.
- No payload tests: I did not run any candidate parser. Effort figures are estimates in the S/M/L scale you defined (S = days, M = 1–2 weeks, L = several weeks).
- Brazilian NF-e, Mexican CFDI, Indian GST e-invoice JSON, Saudi ZATCA, Spanish Verifactu, Japanese Ichitaro/DocuWorks, Chinese CAJ/NH/KDH, UOF and WPS Office files were **not** researched beyond a content-type check. They are unevaluated, not ruled out.
- Scratch files lived in the session scratchpad. This Markdown file is the only repository change.

## 2. Key findings

1. **E-invoices are the strongest lead in this angle.** Germany has required every business to be able to *receive* an EN 16931 e-invoice since 2025-01-01, and issuing becomes mandatory on 2027-01-01 (2028-01-01 for issuers up to EUR 800,000) [R, [BMF FAQ](https://www.bundesfinanzministerium.de/Content/DE/FAQ/e-rechnung.html)]. France made reception mandatory for all VAT-registered companies on 2026-09-01, six weeks ago [R]. Belgium started 2026-01-01 [R] and Poland's KSeF started 2026-02-01 and 2026-04-01 [R]. A pure-XML invoice is unreadable to a human, and nobody offers a Quick Look for it. macOS shows the file as plain text [V].
2. **The competition is arriving as apps, not as Quick Look extensions, and only since January 2025.** "P7M, XML & EU Invoice Viewer" (Eutopix Labs, free, first released 2026-08-04) already handles FatturaPA, UBL, CII, Facturae, KSeF FA(2)/FA(3), P7M/P7S, ASiC/BDOC, EML and MSG [V, App Store text]. "eInvoice Viewer" (Vogelbusch & Co, free, 2025-01-07) and "P7M Converter" (Alvicore, free with a yearly subscription) sit beside it. None of their descriptions claims Quick Look, so the Finder-spacebar niche is open, but not for long.
3. **Outlook `.msg`, `.oft`, `winmail.dat` and `.mbox` are orphaned on macOS and the demand is real.** The system declares no content type for any of them [V]; Apple Mail's own extension covers only `.eml`/`.emlx` [V]. The free "Winmail Viewer - Letter Opener" has 4,953 ratings at 4.75 stars on the US store [V, iTunes lookup]. Quick Look competition is thin and stale: Msg Viewer Pro ($4.99) claims it but was last updated 2024-02-05, before macOS 15 removed `.qlgenerator` plugins [VC, I].
4. **A "Localisation Lens" has no competitor and fits the owner's own 14-language workflow.** XLIFF, PO, TMX and `.xcloc` get raw text only; translators see "what is left" nowhere in Finder. Translation progress, placeholder mismatches and missing plural forms are the same kind of insight as the existing Safety Lens findings.
5. **Apple's native reach is wider than assumed on macOS 27.2.** It ships Quick Look *and* thumbnail extensions for OFD (`public.ofd`, the Chinese fixed-layout format) in `ImageKit.framework` [V]. It previews `.eml`/`.emlx` (Mail extension), `.ics`, vCard, `.xls`/`.doc`/`.ppt` and OpenDocument text [V]. It cannot render PostScript/EPS: my test EPS produced no thumbnail [V], consistent with Apple's removal in Sonoma [R]. OFD is therefore a "test first" item, not a claim.
6. **Four shared building blocks unlock almost everything.** (a) A bounded OLE/CFB reader (MS-CFB): `.msg`, `.oft`, HWP 5. (b) A DER/CMS reader backed by Apple's `CMSDecoder` (no licence): `.p7m`, `.p7s`, `.tsr`, S/MIME inside `.msg`. (c) A *content-sniffed XML dialect* step that upgrades `data.xml` after conservative root-element matching: e-invoices, camt, XLIFF, TMX, MSPDI. (d) The existing bounded ZIP reader plus XML/JSON: Visio, XMind, HWPX, ASiC, XPS, OFD.
7. **The permissive-licence route works for the lead candidates because the specs are open and we write the parsers.** Microsoft's MS-OXMSG/MS-OXTNEF/MS-CFB allow copying for implementations, though the patent covenant (Open Specifications Promise) was not opened here [R]. Hancom's HWP 5.0 spec is free to use but demands an attribution sentence in the UI, manual, help and source [V]. Standards for e-invoices, CAdES/ASiC, ISO 20022 and XLIFF are public. No LGPL/GPL code is needed. Ruled out: PST (libpff is LGPL, the MS-PST route is large), MPP, WordPerfect/Works/Publisher, XPS rendering.
8. **A design wrinkle for the lead:** decision 012 says findings carry typed kinds, counts and lines, "never source values". Invoice arithmetic and balance findings need to reference amounts. Treat this as an amendment request (typed field reference plus typed decimal detail), not a blind implementation.

## 3. Ranked candidates

Fidelity: **facts** = metadata and summary; **text** = extracted body text and structure; **rendered** = a laid-out native view (not a replica of the source application's page layout). Effort: S = days, M = 1–2 weeks, L = several weeks.

| # | Candidate (suffixes) | Audience / regions | macOS native today | Quick Look competitor coverage | Route + licence | Fidelity | Reuses | Effort | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **E-invoice XML**: `.xml` sniffed as EN 16931 UBL/CII (XRechnung, Peppol BIS 3, Factur-X/ZUGFeRD XML), FatturaPA, UBL-TR e-Fatura/e-Arşiv, KSeF FA(3), Facturae; later CFDI, NF-e, Chinese e-fapiao XML | Bookkeepers, SMEs, public-sector suppliers; DE, FR, BE, PL, IT, TR, ES now; BR, MX, CN, ID next | Plain-text preview only (`public.xml` goes to Apple's text provider) [V] | No Quick Look found. Viewer apps only: Eutopix (2026-08), eInvoice Viewer, P7M Converter [V] | Foundation `XMLParser` + own term maps; OASIS UBL 2.1, UN/CEFACT CII, EN 16931, Agenzia delle Entrate XSD; no third-party code | Facts + text + rendered invoice layout | Summary-facts, findings banner, table (lines), outline (fields), source text | M core, +S per dialect | **Lead with** |
| 2 | **Signed containers**: `.p7m` `.p7s` `.p7c` `.tsr`; ASiC-E/S `.asice` `.asics` `.bdoc` `.edoc` `.sce` | Italy (`.xml.p7m` invoices), Estonia and Baltics, EU public sector, legal | None: no system type for any suffix [V] | No Quick Look. Apps: Eutopix, Alvicore P7M Converter, DigiDoc4 (Estonian state client) | Apple Security `CMSDecoder` (system API) + bounded ZIP + `XMLParser`; ETSI EN 319 122/162, RFC 5652, RFC 3161 | Facts + text; payload via #1 | Summary-facts, findings, Files listing, nested preview | M | **Lead with** (paired with #1) |
| 3 | **Mail orphans**: `.msg` `.oft` `winmail.dat` (TNEF) `.mbox` | Anyone receiving Outlook mail from Windows/enterprise senders; legal, HR, public sector; global | None. `.eml`/`.emlx` are covered by Apple Mail's extension, so do not claim them [V] | Msg Viewer Pro ($4.99, stale), BetterZip (`winmail.dat`), legacy QLOutlookMessage [VC, R]; viewer apps, not Quick Look | Own CFB reader + MS-OXMSG/OXTNEF/OXRTFCP (Microsoft Open Specifications); small own MIME parser for mbox; no third-party code | Facts + text | Summary-facts, findings, rendered text, table (headers, links), Files listing | M (`.msg`), +S (TNEF), +S–M (mbox) | **Lead with** |
| 4 | **Localisation files**: `.xlf` `.xliff` `.sdlxliff` `.mqxliff` `.po` `.pot` `.mo` `.tmx` `.tbx` `.resx` `.arb`, Android `strings.xml`, `.xcloc` | Translators, localisation engineers, app developers; global | Raw text only. `.xliff`/`.xlf` have a declared type, the rest none [V] | None found. Poedit ships its own PO extension [R]; editors (Xliff Editor $9.99, XLIFFy) have no Quick Look | `XMLParser`, own PO/MO parsers, `JSONSerialization` for ARB; no dependencies | Facts + text | Table, Profile-style statistics, findings banner, summary-facts | M, then S per format | **Lead with** (distinctive, owner-aligned) |
| 5 | **Bank statements and payment files**: camt.052/053/054, MT940/MT942, OFX/QFX, QIF, BAI2 | Accountants, bookkeepers, treasury; DE and the SEPA zone first | Raw text only [V] | None found (web search only; API not searched) | Own parsers; ISO 20022 XSDs, SWIFT MT field rules; no dependencies | Facts + text + table | Table, Profile, findings, summary-facts | M | **Add** |
| 6 | **Visio**: `.vsdx` `.vssx` `.vstx` `.vsdm` | IT, network and process teams; enterprise | None: no system type [V] | None claim Quick Look; paid viewer apps exist (Nektony $14.99, Enolsoft) [V] | Bounded ZIP + XML (OPC); MS-VSDX / Visio file-format reference | Facts + text; rendered possible (L) | Outline, Files/Tree, summary-facts, diagram renderer (to check) | M text; L drawing | **Add** |
| 7 | **PostScript/EPS**: `.eps` `.ps` | Designers, print, publishers, archives | Cannot render. Type exists but no thumbnail on 27.2 [V]; interpreter removed in Sonoma [R] | Peek (2022, PostScript) [VC]; "EPS Preview" app [R] | Own DSC comment scanner; ImageIO for embedded TIFF previews; never interpret PostScript | Facts + embedded raster preview | Summary-facts, Pages/images | S–M | **Add** |
| 8 | **Mind maps**: `.xmind` `.mm` `.mmap` `.itmz` | Students, consultants, knowledge workers | None; `.mm` is mapped to Objective-C++ source [V] | MindPreview Lite (2017) only [V] | ZIP + JSON/XML; own | Text (outline) | Outline/tree, summary-facts | S–M | **Add** (cheap) |
| 9 | **HWP / HWPX** | South Korea (public sector, schools) | None [V] | No Mac Quick Look found; legacy Intel plugin [R]; new viewer apps | HWPX: ZIP + XML; HWP 5: CFB + raw deflate (system zlib); Hancom spec, attribution required | Facts + text | Rendered text, summary-facts | S–M (HWPX), M (HWP 5) | **Niche** (Korean is not among the 14 languages) |
| 10 | **OFD** (Chinese fixed-layout, e-fapiao) | China | **Apple ships OFD preview + thumbnail extensions on 27.2** [V]; older macOS unknown | None found | n/a | n/a | n/a | n/a | **Niche**: test on macOS 15/26 before any claim |
| 11 | **MOBI / AZW3** | Kindle users, ebook libraries | None [V] | Quick Preview ($2.99), Book Preview ($7.99) [VC] | Own PalmDOC/MOBI/KF8 parser (community docs); Amazon DRM blocks text | Facts + cover + text | EPUB reader presentation | M | **Niche** |
| 12 | Evernote `.enex` · EMF/WMF · EDIFACT/X12/HL7 v2 · MSPDI · CHM · DjVu · ZPL · XBRL | Specialists | Mostly none [V] | CHM: ChmPages (free, 2022); DjVu: DjVu Reader Pro $3.99 [VC] | See section 5 | mixed | mixed | S–L | **Niche** |
| 13 | XPS/OXPS · PST/OST · MPP · WordPerfect/Works/Publisher/LIT/OneNote | Legacy | None [V] | Apps only | Unworkable or off-licence | — | — | L+ | **Rule out** |

Suggested order, if the owner agrees: (1) #1 wave 1 with #2, so the e-invoice view exists before Germany's 2027-01-01 issuing deadline; (2) #3; (3) #4; (4) #5; then #6, #7 and #8 as small additions. Items 1–3 share mainly the findings and summary-facts infrastructure (plus the CMS reader for S/MIME mail), so two parallel owners are feasible.

## 4. Candidate sections

### 4.1 E-invoice reader (rank 1: Lead with)

**What the preview shows.**

- Header: dialect and version badge ("EN 16931 UBL 2.1 · XRechnung 3.0", "FatturaPA 1.2.2 FPR12", "UBL-TR 1.2"), invoice number and type (invoice, credit note), issue and due dates, currency, seller to buyer with VAT/tax IDs, totals (net, VAT, gross, prepaid, payable).
- **Invoice** mode: a laid-out native view in a conventional invoice order (parties, lines, VAT breakdown, totals, payment block, notes). It is built from the data fields, not from the issuer's stylesheet.
- **Lines** mode: the sortable, filterable table, with Profile-style statistics (largest lines, VAT-rate mix).
- **Fields** mode: an outline of every business term with its EN 16931 code (BT-xx) and the element path, for integrators and accountants.
- **Source** mode: highlighted XML.
- **Insight layer** (typed findings, offline, labelled "structure and arithmetic only, not legal validation"):
  - Arithmetic: line extension amounts against the line net total, allowances and charges, per-category VAT sums, grand totals and the payable amount, using `Decimal`. These correspond to EN 16931 business rules such as BR-CO-10, -13, -15 and -16 [I; the rule IDs are from my knowledge of the CEN rule set, check against the published Schematron].
  - Missing mandatory terms from a short fixed list per dialect (seller, buyer, payment means, buyer reference for XRechnung).
  - IBAN length and ISO 13616 mod-97 checksum; BIC present; due date earlier than issue date; payment terms against due date; document currency against tax currency.
  - Tax-ID shape and, where the algorithm is public, checksum plausibility (Polish NIP, Italian partita IVA, Turkish VKN). Offline plausibility only, never registry validation.
  - Soft "worth a look": seller IBAN country differs from seller country (legitimate for several neobanks, so severity is informational).
  - Embedded attachments (base64 PDFs in `AdditionalDocumentReference`, FatturaPA `Allegati`): listed by name, size and type, never decoded to disk; executable-looking names flagged; hidden Unicode in names and in the IBAN (reuse `HiddenCharacters`).
  - A stylesheet is embedded (see Turkish note) and was **not** run.
  - A digital signature element is present and was **not** verified.

**Demand evidence.**

| Market | Fact | Label and source |
|---|---|---|
| Germany | Every domestic business must be able to receive an e-invoice since 2025-01-01; a mailbox suffices. Issuing: "other" invoices allowed to 2026-12-31, to 2027-12-31 if prior-year turnover is up to EUR 800,000. | [R] [BMF FAQ](https://www.bundesfinanzministerium.de/Content/DE/FAQ/e-rechnung.html); BMF letter of 2025-10-15 [R](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/Umsatzsteuer-Anwendungserlass/2025-10-15-einfuehrung-obligatorische-e-rechnung.pdf?__blob=publicationFile&v=3) |
| France | 2026-09-01: all VAT-registered companies must be able to receive; large and mid-size companies must issue. 2027-09-01: SMEs and micro-enterprises must issue. Accepted formats: Factur-X, UBL, CII. | [R] [economie.gouv.fr](https://www.economie.gouv.fr/tout-savoir-sur-la-facturation-electronique-pour-les-entreprises), [impots.gouv.fr guide](https://www.impots.gouv.fr/sites/default/files/media/1_metier/2_professionnel/EV/2_gestion/290_facturation_electronique/guide_pratique_facturation_electronique.pdf) |
| Belgium | Structured B2B e-invoicing (Peppol BIS 3 preferred) mandatory since 2026-01-01. | [R] vendor blogs: [Forvis Mazars](https://www.forvismazars.com/be/en/insights/newsletters-client-alerts/newsletters/mandatory-b2b-e-invoicing-in-belgium) |
| Poland | KSeF issuing mandatory from 2026-02-01 (2024 sales above PLN 200m) and 2026-04-01 (everyone else); reception from 2026-02-01 for all; monthly sales up to PLN 10,000 exempt from issuing until the end of 2026. | [R] [ksef.podatki.gov.pl](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/zakres-obowiazkowego-ksef/); [V] [Gov.pl KAS](https://www.gov.pl/web/kas/obowiazkowy-ksef-odroczony-do-1-lutego-2026-r) confirms the enacted law sets 2026-02-01 |
| EU (ViDA) | In force 2025-04-14; digital reporting for cross-border B2B from 2030-07-01; member states may mandate domestic e-invoicing earlier under conditions; national reporting aligns by 2035-01-01. | [V] [European Commission](https://taxation-customs.ec.europa.eu/taxation/vat/vat-digital-age-vida_en) |
| Italy | B2B e-invoicing through SdI since 2019; files are XML, optionally signed (`.p7m`). One unofficial article cites more than 2.4 billion invoices in 2023; I found no official count. | [R] [pmi.it](https://www.pmi.it/impresa/contabilita-e-fisco/307732/fattura-elettronica-bilanci-roadmap-e-novita-da-luglio.html) |
| Turkey | e-Fatura/e-Arşiv are UBL-TR XML. Thresholds disagree between sources (gross sales of TL 3m, or net TL 5m; transition 2026-07-01). **I could not verify the current threshold from a GİB source.** | [R] [Ideasoft](https://www.ideasoft.com.tr/e-ticaret-icin-e-fatura-zorunlulugu/), [Faturaport](https://faturaport.com/blog/e-fatura/1-temmuz-2026-e-fatura-zorunlulugu-gecis-limitleri) |
| China | The digitalised invoice ("数电发票") is issued as PDF, OFD and XML; the digitally signed XML is the accounting-valid file, and the XML is "machine-readable, not human-readable". | [R] [State Taxation Administration](https://fgk.chinatax.gov.cn/zcfgk/c100012/c5236067/content.html) |
| Indonesia | Coretax uses XML bulk import for tax invoices (up to 1,000 per file as of early 2025). | [R] [DDTC](https://news.ddtc.co.id/berita/nasional/1808220/coretax-diperbarui-pkp-bisa-unggah-1000-faktur-pajak-per-file-xml) |

"How many businesses will suddenly receive XML they cannot read?" I could not find a sourced headcount, so I give none. The qualitative case is solid: the German and French *receiving* duties apply to every VAT-registered business including those that never issue an e-invoice, and an XRechnung "has no visual component" [R, [gruender.de](https://www.gruender.de/buchhaltung/e-rechnung-empfangen-2025/)]. The mitigating fact: France routes invoices through certified platforms and German accounting software imports them, so many recipients never open the raw file. The Quick Look case is the occasional human check: the accountant, the owner-manager, the person comparing an amount before paying.

**What people use today.** Web visualisers, accounting packages and, since 2025, small free apps (above) [V]. Whether any web viewer uploads the file I could not verify, so the "nothing leaves your Mac" contrast is a positioning argument, not a finding. Apple's text preview shows the raw XML [V].

**Native.** `.xml` is `public.xml`, previewed as text by Apple's `QLPreviewGenerationExtension` [V]. SpacePane already registers the generic XML type (`data.xml`).

**Implementation route.**

- Specs: [OASIS UBL 2.1](https://docs.oasis-open.org/ubl/UBL-2.1.html), UN/CEFACT CII D16B, EN 16931 semantic model and syntax bindings, Italy's FatturaPA technical specifications and XSD (Agenzia delle Entrate), Polish FA(3) schema, Facturae 3.2.x, UBL-TR 1.2 (GİB). I opened none of these specification pages except the Peppol one below. Treat the namespace strings in this section as [I] to confirm against the schemas.
- Architecture: map every dialect to one EN 16931-shaped `InvoiceModel`. FatturaPA, UBL-TR, FA(3) and Facturae each get a thin adapter plus a term-label table. Data-driven term maps keep the code small and make new dialects an S job.
- **Detection stays conservative.** Never by filename. Read at most the first 64 KB with an aborting `XMLParser`; match the *exact* root QName (namespace plus local name), then require one expected structural child before claiming. Examples: UBL `Invoice-2`/`CreditNote-2` with `cbc:CustomizationID`; CII `CrossIndustryInvoice` in the `urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100` namespace; FatturaPA `FatturaElettronica` with `versione` `FPR12`/`FPA12`. Peppol BIS 3 invoices must carry a `CustomizationID` beginning `urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0` [V, [Peppol BIS 3.0](https://docs.peppol.eu/poacc/billing/3.0/syntax/ubl-invoice/cbc-CustomizationID/)]. XRechnung uses an `urn:xeinkauf.de:kosit:xrechnung_` CustomizationID [I]. Turkish UBL-TR is UBL with `CustomizationID` `TR1.2` [I]. On any mismatch, partial parse or size over a cap, fall back to the generic XML tree.
- **Never run the embedded stylesheet.** A UBL-TR file typically carries an XSLT as a base64 `EmbeddedDocumentBinaryObject` [R: a Turkish tax-practice article and a browser-extension page both describe it; I could not open GİB's own package]. An auditor warns that an XSLT can show information that is not in the XML [R, [Turkish audit-blog summary](https://www.muhasebetr.com/yazarlarimiz/erhanselim/016)]. SpacePane shows values from the data fields only, and says so in a finding. That matches the repository rule not to execute document-supplied code.
- Bounds: DTD and external entities disabled; cap on elements, depth, text length and embedded-attachment count; base64 attachments counted, not decoded; `Decimal` arithmetic.
- Wave plan: W1 UBL + CII (covers XRechnung, Peppol, Factur-X/ZUGFeRD XML, French and Belgian traffic) and FatturaPA, together with #2. W2 UBL-TR, KSeF FA(3), Facturae. W3 CFDI 4.0, NF-e, Chinese e-fapiao XML, Indonesian Coretax XML, after the schemas are checked.
- Licence: none needed beyond Apple frameworks; the standards are public. Cost to count: every business term label is a localised string in 14 languages, roughly 60–80 labels for the EN 16931 core [I].

**Safety and privacy.** Invoices are financial personal data. No content thumbnails (a generic "invoice" icon with the dialect badge at most). Offer IBAN concealment with a reveal toggle and a copy action for the exact value, in the style of secret concealment (owner decision). No attachment extraction.

**Risks and unknowns.**

- Wording: a "no problems found" banner can be read as compliance. Use "checks passed: arithmetic, IBAN structure", never "valid".
- The Schematron rule set is larger than the fixed rules above; false negatives are expected and must be disclosed.
- `.xml` routing is shared with Apple's provider and with other apps; the repository already treats provider conflicts as a known pain, and the user cannot be promised which provider wins.
- A new "content-sniffed logical type" is a shared-contract change: the catalog keys types by suffix and UTType, and the per-type switches (decision 002) need an "E-invoice" type that sits *above* `data.xml` without bypassing a disabled `data.xml`.
- Factur-X/ZUGFeRD *PDF* invoices are `com.adobe.pdf`, owned by Apple. The most valuable check there, "does the embedded XML agree with the visible PDF?", is out of reach. Only a standalone extracted XML is claimable.

### 4.2 Signed containers: CAdES `.p7m`/`.p7s`, timestamp tokens, ASiC-E (rank 2: Lead with)

**What it shows.** A "Signature" summary: who signed (subject and issuer from the signer certificate), signing time claimed by the signer, signature and digest algorithms, certificate validity window, number of certificates included, and the file list of the payload (names, sizes, types). The payload previews through its own presentation: a FatturaPA XML opens in the e-invoice view; a text file as text; a PDF as a name, size and page count (and, as a stretch, a bounded first-page raster from PDFKit, an Apple framework).

- Honest label, always visible: "Signature checked offline. Certificate trust and revocation were not checked (no network)."
- Findings: SHA-1/MD5 digests; certificate expired relative to the signing time (or "no trusted timestamp, so the signing time is only the signer's claim"); self-signed signer; detached signature with no content present (`.p7s`); several signers; signature count; nested `.p7m`.
- ASiC-E: list `META-INF/signatures*.xml` signers, signing times and certificate subjects; recompute SHA-256 of each file against the `ds:Reference` digests. "Files match the signed digests: yes/no" is cheap and is a genuine tamper check. The `SignedInfo` signature value needs Exclusive XML Canonicalization and is **not** verified in wave 1; say so.
- Timestamp tokens (`.tsr`, RFC 3161): authority, time, hash algorithm and the hash of the stamped data. S.

**Demand evidence.**

- Italian invoices travel as `*.xml.p7m` when signed [R, [pmi.it](https://www.pmi.it/impresa/contabilita-e-fisco/307732/fattura-elettronica-bilanci-roadmap-e-novita-da-luglio.html)]; the invoice itself is untouchable on a Mac without an app.
- Estonia: new containers are `.asice`, older ones `.bdoc`; the state's DigiDoc4 Client is the way to open them on a Mac; a ZIP tool shows the files but skips signature checks [R, [id.ee](https://www.id.ee/en/article/what-is-the-difference-between-digitally-signed-documents-with-bdoc-and-asice-extensions/); [Mac App Store](https://apps.apple.com/us/app/digidoc4/id1370791134?mt=12)].
- Competitor apps exist for P7M/ASiC but none claim Quick Look [V, App Store text]: [Eutopix](https://apps.apple.com/us/app/p7m-xml-eu-invoice-viewer/id6793142246?uo=4) (P7M/P7S, TSD/M7M, ASiC/BDOC/EDOC/DDOC), [Alvicore P7M Converter](https://apps.apple.com/us/app/p7m-converter/id6761845334?uo=4).
- Native: no system type for `.p7m`, `.p7s`, `.p7c`, `.tsr`, `.tsq`, `.asice`, `.asics`, `.bdoc`, `.edoc`, `.sce` [V]. Apple's `Security.qlgenerator` covers PKCS#12 and certificates, not CMS [V].

**Route.**

- CAdES/CMS: Apple Security framework `CMSDecoder` (functions seen in Apple's documentation index: `CMSDecoderCreate`, `CMSDecoderFinalizeMessage`, `CMSDecoderCopyContent`, `CMSDecoderCopySignerCert`, `CMSDecoderCopySignerTimestampCertificates`, `CMSSignerStatus`) [R, [CMSDecoder](https://developer.apple.com/documentation/security/cmsdecoder.md), [CopyContent](https://developer.apple.com/documentation/security/cmsdecodercopycontent(_:_:).md), [CopySignerCert](https://developer.apple.com/documentation/security/cmsdecodercopysignercert(_:_:_:).md)]. I could not confirm `CMSDecoderCopySignerSigningTime` from the pages I reached (the header returned 404), so a small bounded DER walker for the signed attributes is the fallback. No licence is involved.
- Italian `.p7m` files often use BER indefinite-length encoding and may be base64-wrapped; test both through `CMSDecoder` first [I].
- ASiC: the existing bounded ZIP reader plus `XMLParser` on the XAdES; `SecCertificateCreateWithData` for certificate fields.
- Standards (free): ETSI EN 319 122 (CAdES), EN 319 162 (ASiC), RFC 5652 (CMS), RFC 3161 (timestamps).

**Safety and privacy.** Never extract the payload to disk. The sandbox has no network entitlement, so trust evaluation must be set not to fetch (revocation and intermediate certificates): to be prototyped on a Mac (`SecTrustSetNetworkFetchAllowed` false) [I] because a blocked fetch could stall. No content thumbnails.

**Risks.**

- Legal weight: "valid" has a legal meaning under eIDAS that needs trusted lists and revocation. Use "intact/matches" language only, and have the wording reviewed.
- `CMSDecoder` behaviour on large or hostile inputs under the extension's memory limit is unmeasured.

### 4.3 Mail Lens: Outlook `.msg`/`.oft`, `winmail.dat`, `.mbox` (rank 3: Lead with)

**What it shows.**

- Header block: from, to, cc, subject, sent date, importance, message class (`IPM.Note`, `.Appointment`, `.Contact`, `.Task`). Bcc recipients appear only if the file contains them.
- Body: plain text; for RTF-only mail, the decompressed RTF as styled text; for HTML mail, an extracted-text view with a table of links (visible text, destination, host). No web rendering (no WKWebView, per the constraints), so images and layout are not reproduced. Fidelity is text and facts.
- Attachments: name, size, declared type, inline or not, embedded `.msg` count; calendar and contact messages as small fact cards (start, end, location, attendees; name, addresses, numbers).
- Transport headers (`PidTagTransportMessageHeaders`): the Received chain and any `Authentication-Results` (SPF/DKIM/DMARC) shown as reported, never judged.
- **Insight layer** (phishing-relevant facts, offline, labelled "heuristics, not a verdict"): display name versus address mismatch; Reply-To domain differs from From; mixed-script or punycode sender domain (reuse the hidden-Unicode and confusable classifiers); link text names a different host than the destination; IP-literal, `userinfo@` and shortener hosts; `javascript:`/`data:` links; attachments with double extensions, scripts, disk images or archives with executables (reuse the archive-risk logic), HTML attachments, OneNote `.one` attachments and macro-enabled Office suffixes; send date in the future.
- S/MIME-signed `.msg` carries the message as an `smime.p7m` attachment, which hands straight over to candidate #2.
- `.mbox`: a message list table for the first N messages (date, sender, subject, size) with a first-message preview. Apple Mail exports mailboxes as an `.mbox` *package*; Gmail Takeout produces one very large file.
- Rights-protected (`.rpmsg`) and encrypted messages: say so, show nothing else.

**Demand evidence.**

- Native: no system type for `.msg`, `.oft`, `.dat`, `.mbox` [V]; `.eml`/`.emlx` have Apple's Mail extension (`com.apple.mail.email`, `com.apple.mail.emlx`) [V].
- Letter Opener "Winmail Viewer" (opens Winmail.dat, MSG, XPS): 4,953 ratings, 4.75 stars, US store [V]. A new "Winmail Viewer - TNEF Opener" appeared 2026-07-16 [V]. "MSG Viewer - Email Opener" (released 2026-01-30, subscription) handles `.msg`, `.oft`, TNEF, `.eml`, `.mbox`, `.mht` but uses Quick Look only to preview attachments [VC].
- Quick Look competitors: Msg Viewer Pro, $4.99, "Quick look msg, winmail, mht and eml files", min macOS 12, last updated 2024-02-05 [VC]. That predates macOS 15's removal of `.qlgenerator`, so it probably no longer previews on current macOS (my inference, untested). BetterZip previews `winmail.dat` [VC, landscape doc]. QLOutlookMessage is a legacy generator, listed as Intel-only [R, [search result](https://www.twistermc.com/43584/how-to-read-outlook-msg-files-on-your-mac-or-windows-for-free/)].
- One forum report that only `.eml`/`.emlx` preview on a Mac [R, [DEVONthink forum](https://discourse.devontechnologies.com/t/msg-files-preview-works-perfect-on-my-iphone-but-not-on-my-mac/81613)].

**Route.**

- Own bounded CFB reader from [MS-CFB] (header, FAT, mini-FAT, DIFAT, directory entries; cycle detection; caps on sectors, streams, depth). Then [MS-OXMSG] property streams: `__properties_version1.0` (header 32 bytes for the top-level message, 24 for embedded, 8 for attachment and recipient storages; 16-byte property entries), variable-length `__substg1.0_<tag><type>` streams (Unicode `001F`, string8 `001E` with the message code page), `__recip_version1.0_#n`, `__attach_version1.0_#n`; compressed RTF [MS-OXRTFCP] (LZFu; a few dozen lines). I know these layouts from memory [I]; the specs are the authority.
- TNEF: [MS-OXTNEF], signature `0x223E9F78`, attribute records; attachments and the MAPI property blob.
- Spec access: [MS-OXMSG](https://msopenspecs.microsoft.com/files/MS-OXMSG/%5bMS-OXMSG%5d-210422.docx), [MS-OXTNEF](https://msopenspecs.microsoft.com/files/MS-OXTNEF/%5bMS-OXTNEF%5d-240820.docx), [MS-OXCMSG](https://msopenspecs.microsoft.com/files/MS-OXCMSG/%5bMS-OXCMSG%5d-230815.docx). The IP notice in these documents allows copies "to develop implementations" and disclaims trade-secret claims; patent licences come only if the Open Specifications Promise or Community Promise covers the document [R]. **I did not open the Promise text; the owner should read it before relying on it.**
- mbox needs a small RFC 5322/2045 MIME parser (multipart, quoted-printable, base64, RFC 2047 encoded words, charsets). Foundation has none. It is also the parser a future `.eml` insight layer would need.
- No third-party code or licence.

**Safety and privacy.** Email is the most sensitive content in this angle. No content thumbnails; secret concealment applies to the body (password-reset links, tokens); links are shown, never clickable (decision 025); attachments are listed, never extracted; the copy action needs a "Copy Concealed Text" equivalent.

**Risks.** Large `.msg` files with big attachments (cap by directory-stream size, never load whole attachments); OLE-embedded objects; named properties (`__nameid_version1.0`) are needed for appointment details and add effort; HTML-to-text fidelity; IRM-protected mail.

### 4.4 Localisation Lens: XLIFF, PO/MO, TMX, `.xcloc` and friends (rank 4: Lead with)

**What it shows.**

- Header facts: source language, target language(s), unit counts, generator (Xcode, Poedit, Weblate, Crowdin, memoQ, Trados), last-modified or `PO-Revision-Date`.
- A completeness readout: translated / needs review / untranslated / fuzzy counts and a percentage, per target language (multi-language `.xcloc` and `.arb` families).
- A table of units (key or context, source, target, state, note, placeholders), filterable by state.
- **Findings** (informational by default): placeholder mismatch between source and target (`%@`, `%1$d`, `{name}`, ICU `{count, plural, …}`, XLIFF inline `<x/>`/`<g>`/`<ph>`/`<pc>`, balanced HTML); target identical to source; leading or trailing space and punctuation mismatches; target much longer than source (UI overflow risk); missing plural categories for the target language (CLDR); PO `fuzzy` and obsolete `#~` entries; duplicate keys; PO charset header mismatch; hidden Unicode in a target (reuse `HiddenCharacters`).
- TMX: language pairs and translation-unit counts, plus a sample. Termbases (TBX): concept and term counts.
- The existing `.strings`, `.stringsdict` and `.xcstrings` previews could reuse the same statistics, so the Lens improves types that are already shipped.

**Demand evidence.** Honest answer: modest, concentrated and underserved. I found no audience-size figure. Poedit's own release notes say 3.5.1 added a modern Quick Look extension (required on macOS 15) [R, [Poedit NEWS](https://sources.debian.org/src/poedit/3.9-2/NEWS)], which covers PO for Poedit users only. XLIFF has editors with no Quick Look: Xliff Editor ($9.99, last updated 2026-08-27) and XLIFFy [V, R]. A ProZ thread asks for a free XLIFF viewer showing statuses and statistics [R, [ProZ](https://mac.proz.com/forum/cat_tools_technical_help/354670-is_there_a_free_xliff_viewer_that_has_these_features.html)]. Native: `.xliff`/`.xlf` carry a declared type on this Mac, `.po`, `.mo`, `.tmx`, `.resx`, `.arb`, `.sdlxliff`, `.tbx` do not [V]; all fall back to raw text [I]. The owner's own 14-language workflow is a built-in test audience.

**Route.** Foundation `XMLParser` (streaming) for XLIFF 1.2/2.x, SDLXLIFF/MQXLIFF (XLIFF 1.2 plus vendor attributes), TMX 1.4, TBX, RESX and Android `strings.xml` (including `<plurals>` and `translatable="false"`); `JSONSerialization` with caps for ARB (`@@locale`, `@key` metadata); own PO parser (the gettext manual describes the format); own MO parser (small binary: magic `0x950412de`, two offset tables). A small embedded CLDR plural-category table for the target languages, starting with the 14 app languages. Standards: OASIS XLIFF 1.2/2.1, GNU gettext, LISA/GALA TMX, ISO 30042 TBX, all public. `.xcloc` is a directory package with `Localized Contents/*.xliff`; its content type is not confirmed here, so check on the Mac [I].

**Safety and privacy.** Translated copy can be confidential product text, so no content thumbnails. A *counts-only* thumbnail (language pair and a progress ring) leaks no content and would be a distinctive visual. Strings in the file are user content and are never translated or reformatted.

**Risks.** CAT-tool dialect variety; placeholder reordering is legitimate in some languages (keep it informational); CLDR table maintenance; PO plural-forms expressions.

### 4.5 Bank statements and payment files (rank 5: Add)

**What it shows.** Account (IBAN with checksum result, BIC), statement id and period, opening and closing balances; a transaction table (booking and value date, signed amount, counterparty, remittance information, bank transaction code, end-to-end id); Profile-style summary (inflow, outflow, count, largest entries, per-day totals). **Findings:** opening balance plus entries does not equal closing balance; entry count differs from the declared total; entries outside the statement period; duplicate entries; mixed currencies; IBAN checksum failure; hidden Unicode in references. The "balance continuity" check is the distinctive part: it is the first thing an accountant verifies.

**Formats.** camt.052/053/054 (ISO 20022 XML, namespace `urn:iso:std:iso:20022:tech:xsd:camt.053.001.xx` [I]); MT940/MT942 including the German structured `:86:` subfields; OFX 1.x (SGML-like) and 2.x (XML); QIF; BAI2. pain.001/008 (payment initiation, SEPA credit transfers and direct debits) are a natural W2 sibling.

**Demand evidence.**

- Bank-to-customer MT formats are being retired in EBICS 3.7 (Commerzbank: since 2025-11-23, with its MT940/942 to camt switch planned for Q3 2026) [R, [Commerzbank](https://www.commerzbank.de/service/umstellung-von-mt-formaten-auf-camt-formate-in-ebics/)]. UniCredit keeps MT940/MT942 pick-up until November 2026 [R, [UniCredit](https://gtgdownload.unicreditgroup.de/QG_UC_eBanking_prime_camt_DE.pdf)]. DATEV moves its programs from 2026-07-13 and SEPA 3.7 becomes mandatory from November 2026 [R, [DATEV](https://www.datev.de/web/de/berufsgruppenuebergreifend/gesetzliche-themen/payment/kontoumsaetze-bereitstellen-neues-format)]. Accountants and bookkeepers are meeting camt.053 XML where they used to see MT940 or CSV.
- A web search found no Mac app or Quick Look extension that previews OFX, QFX, QIF, MT940 or camt.053; importers (iFinance) and a Windows analyser exist [R].
- Native: no system types [V]; `.xml` camt files get Apple's text preview.

**Route.** `XMLParser` for camt and OFX 2.x, a line parser for MT940/QIF/OFX 1.x; no dependencies. Dialects: camt versions differ and banks fill fields differently, so tolerate missing fields. Detection by exact root namespace (conservative, as in 4.1).

**Safety and privacy.** Account numbers and balances are financial personal data: no content thumbnails; same concealment-with-reveal option as invoices; `Copy Concealed Text` equivalent.

**Risks.** Sign conventions (`CdtDbtInd`, reversals); multi-currency statements; bank-specific MT940 `:86:` layouts.

### 4.6 Visio `.vsdx` (rank 6: Add)

**What it shows.** Page list (including hidden and background pages), shapes per page, masters and stencils used, layers, author, company, last-saved-by and dates from `docProps`, the document's Visio version. **Shape text** in reading order as an outline (page, then shape with master name, then text). **Shape data** (the property rows, often the real content in IT and network diagrams) as a table. **Hyperlinks** (shape, address, sub-address, description; external addresses flagged, never clickable). **Comments**. **Connections** (from-shape to to-shape). A "document hygiene" panel: hidden layers or pages, external links, embedded OLE objects, macros (`.vsdm`), personal information.

**Rendered level (stretch, L).** Visio stores positions in inches (`PinX`, `PinY`, `Width`, `Height`, `Angle`). A position-preserving "Diagram" mode could draw each top-level shape as its bounding box with its text and connect shapes with lines, falling back to the outline for unsupported geometry (formulas, NURBS, splines). I did not read the native Diagram renderer, so whether it accepts explicit coordinates is unknown; if not, a small CoreGraphics view is the alternative. The package usually contains `docProps/thumbnail.emf` [R, [LoC format description](https://loc.gov/preservation/digital/formats/fdd/fdd000021.shtml)], which would need the EMF renderer in section 5 and would show content (see privacy).

**Demand evidence.** I found no usage figure. Native: no system type for `.vsd`, `.vsdx`, `.vssx` [V]. Competitors: paid or free viewer apps with no Quick Look claim, e.g. VSD Viewer for Visio Drawings (Nektony, $14.99, last updated 2022-12-21), VSD&VSDX Viewer (Enolsoft, free), Visio File Viewer (free) [V, App Store text]. No Mac Quick Look for Visio found [V, API]. The case is the person on a Mac who is e-mailed a diagram from a Windows colleague.

**Route.** Bounded ZIP + `XMLParser`; Open Packaging Conventions; [Visio file format reference](https://learn.microsoft.com/en-us/office/client-developer/visio/visio-file-format-reference) and MS-VSDX [R]. Legacy binary `.vsd` is out (the open implementation, libvisio, is MPL/LGPL from memory [I]).

**Safety and privacy.** Diagrams of networks and systems are sensitive; no content thumbnails. Never open OLE objects or macros.

**Risks.** Geometry formulas make faithful drawing a rabbit hole; set the outline as the product and the drawing as an optional bonus.

### 4.7 PostScript/EPS facts and embedded preview (rank 7: Add)

**What it shows.** DSC header fields: `%%Title`, `%%Creator`, `%%CreationDate`, `%%For`, `%%BoundingBox` / `%%HiResBoundingBox` (converted to mm and inches), `%%Pages`, `%%LanguageLevel`, `%%DocumentFonts` and needed resources (the font list, useful to print designers), process and custom colours (spot-colour names such as Pantone). If the file carries a preview, show it: DOS EPS Binary header (magic `0xC5D0D3C6`) with a TIFF or WMF preview, EPSI `%%BeginPreview` bitmap, or Photoshop `%ImageData`. Otherwise say plainly "no embedded preview; macOS cannot render PostScript".

**Native status.** Apple's Preview dropped PostScript/EPS in Ventura [R, [TidBITS](https://tidbits.com/2022/10/27/preview-in-ventura-drops-support-for-postscript-and-encapsulated-postscript-files/)]; Sonoma removed the converter and `PSNormalizer` per Apple's release notes as quoted by [Eclectic Light](https://eclecticlight.co/2023/09/25/postscripts-sudden-death-in-sonoma/) [R]. On this Mac the EPS content type exists (`com.adobe.encapsulated-postscript`) and `qlmanage -t` on a valid tiny EPS produced nothing [V]. Adobe Illustrator `.ai` is PDF-compatible and has a system generator [V].

**Competitors.** Peek lists PostScript (last updated 2022-04-02) [VC, landscape doc]; "EPS Preview" is described only in a Japanese blog [R, [ameblo](https://ameblo.jp/mymacsoftware/entry-12975288316.html)]; the landscape doc lists EPS under paid niche apps. Designers also report missing EPS previews on Sequoia [R, [Adobe community](https://community.adobe.com/t5/illustrator-discussions/mac-preview-icon-not-working-with-adobe-illustrator-eps-files/m-p/14660528/highlight/true)].

**Route.** Own DSC comment scanner reading the first and last 64 KB (honouring `(atend)` and `%%+` continuations) and ImageIO for the embedded TIFF. **Never interpret PostScript**: the language is executable, and the repository forbids running document code. Without a preview the value is facts only; with one it is a real thumbnail-quality image. Licence: none.

**Risks.** Many EPS files have no embedded preview (modern Illustrator saves can omit it); old Mac EPS keep the PICT preview in the resource fork, which the sandboxed reader cannot see [I]. Set expectations honestly in the UI.

### 4.8 Mind maps (rank 8: Add, cheap)

**What it shows.** An outline of sheets and topics (central topic, branches, depth), notes, labels and markers, task progress, link and attachment counts (links displayed, never clickable), relationship lines as a list; summary-facts with sheet and topic counts.

**Formats.** `.xmind` (Zen/2020+): ZIP with `content.json` (an array of sheets, `rootTopic`, `children.attached`), `metadata.json`, `manifest.json`, `Thumbnails/thumbnail.png`; legacy files use `content.xml` [R, [FileInfo](https://fileinfo.com/extension/xmind), [Obsidian XMind Open plugin](https://www.obsidianstats.com/plugins/xmind-open)]. FreeMind/Freeplane `.mm` is XML (`<map><node TEXT=…>`) [I]. MindManager `.mmap` and iThoughts `.itmz` are ZIPs with an XML map [I]. OPML is already supported.

**Wrinkle.** macOS maps `.mm` to Objective-C++ source [V]. SpacePane may already treat `.mm` as source code, so the mind-map reading needs a sniff for a leading `<map version=` before it wins.

**Privacy.** The embedded XMind thumbnail shows map content, so do not use it as a Finder thumbnail.

**Demand.** No figures found. MindPreview Lite (2017) is the only Quick Look hit; XMind's own app description does not mention Quick Look [V]. Effort is small because it reuses the outline, but the audience case is thin: treat as a low-risk filler.

### 4.9 HWP / HWPX (rank 9: Niche, regional)

**Verified terms.** Hancom's *Hwp Document File Formats 5.0* (revision 1.3, 2018-11-08) states that anyone may read, copy, distribute and use it; distribution is limited to unmodified copies; products developed from it must carry an attribution sentence in the UI, manual, help and source (or in whichever of these exist), which I translate as "This product was developed with reference to Hancom's HWP document file (.hwp) public document"; Hancom reserves the right to act against anyone who obtains exclusive rights from results of the spec and asserts them against Hancom; Hancom gives no accuracy warranty. The copyright for what a developer builds stays with the developer [V, read in Korean on PDF page 6 (document page 1)]. The same page notes that HWPML became the Korean national standard KS X 6101:2011 as OWPML [V]. Spec: [Hancom PDF](https://cdn.hancom.com/link/docs/한글문서파일형식_5.0_revision1.3.pdf).

**What it would show.** HWP 5 is an OLE/CFB file; the spec says the `PrvText` stream holds a Unicode preview text and `PrvImage` holds a BMP or GIF preview image (sections 3.2.6 and 3.2.7) [V]. That gives an instant, cheap first paint: the preview text and image before any body parsing. Then extracted body text from `BodyText/Section*` (raw-deflate compressed when the header flag is set), summary information (title, author, dates), and findings for encrypted or distribution-only (read-only) documents, embedded scripts and OLE objects. HWPX is ZIP + XML (OWPML), `Contents/section0.xml`, with a `Preview/PrvImage.png` [R, [HWPX structure notes](https://news.hada.io/topic?id=19448); the `PrvText.txt` part is unconfirmed]. Fidelity: facts and text, not page layout.

**Demand.** I did not find a population figure. Native: no system type for `.hwp`, `.hwpx` [V]. A new free "HWP Viewer - Hangul hwp·hwpx" (released 2026-10-06) is aimed at iPhone/iPad; its Quick Look mention is for the iOS Files app [V]. A legacy "hanwordviewer QuickLook Generator" is listed as Intel-only [R]. No Mac Quick Look extension found.

**Verdict.** Technically cheap (S–M for HWPX, M for HWP 5) and licence-clean with attribution, but Korean is not among the chosen interface languages. Do it only if the owner adds Korean or finds a Korean-market channel.

### 4.10 OFD (rank 10: test first)

macOS 27.2 contains `OFD_Preview.appex` and `OFD_Thumbnail.appex` in `ImageKit.framework` with `QLSupportedContentTypes = public.ofd` ("Open Fixed-layout Document", suffix `ofd`, MIME `application/ofd`) [V, local `Info.plist` and CoreTypes]. A minimal hand-made OFD I generated produced no thumbnail from `qlmanage -t`; that is inconclusive (my file may be invalid) [V]. Which macOS release introduced it is unknown, and I found no Apple note or press mention of OFD support [R, searches in English and Chinese]. So: **test real e-fapiao OFD files on macOS 15, 26 and 27 before any decision.** If Apple's preview works only on the newest releases, an OFD reader would still serve the 15–26 range; if it works everywhere, rule it out. The format (GB/T 33190-2016, ZIP + XML) is cheap to parse; the invoice XML inside matters more and belongs to the e-invoice reader's wave 3.

### 4.11 MOBI / AZW3 (rank 11: Niche)

MOBI is a PalmDB container: record 0 holds the PalmDOC header (compression none, PalmDOC LZ77, or HUFF/CDIC), a MOBI header with an encryption type and EXTH records (author, title, cover offset, ASIN). AZW3/KF8 adds a second header and HTML flows. Kindle's KFX is a different, DRM-heavy container. Amazon removed "Download & Transfer via USB" for purchased books on 2025-02-26, so fewer protected AZW3 files reach computers [R, [heise](https://heise.de/-10281763), [Android Authority](https://www.androidauthority.com/kindle-download-tool-3526576/)]. DRM-free files can be read; DRM files give metadata, cover and a clear "protected" finding. Competitors: Quick Preview: Folder Preview ($2.99) lists MOBI/AZW/AZW3 [VC, V]; Book Preview ($7.99) covers MOBI [VC]. libmobi is LGPL [I], so an own parser from community documentation (MobileRead wiki, not a formal spec) is the route: M. The audience is shrinking and well served; Niche.

## 5. Niche candidates (one paragraph each)

- **Evernote `.enex`**: XML export of notes (title, tags, ENML text, base64 resources). A note list with text and an attachment inventory is S. `com.evernote.enex` is declared on this Mac by the Evernote app [V]; Apple Notes can import ENEX [I]. Audience is migration-driven and fading. Streaming parse only; attachments are never decoded.
- **EMF/WMF**: no system type [V]. MS-EMF/MS-WMF are open specifications; a bounded record player drawing polylines, rectangles, text and bitmaps through CoreGraphics is M–L. Standalone files are rare for Mac users; the value is mostly as the Visio and Office thumbnail format. No competitor claim found (API not searched).
- **EDIFACT / X12 / HL7 v2**: delimiter-based segment messages. A segment tree with plain-language names from a small dictionary (EDIFACT INVOIC/ORDERS/DESADV; X12 810/850/856; HL7 MSH/PID/OBX) is M. HL7 carries protected health data, so concealing patient identifiers by default would be the differentiator. I found no audience or competitor evidence (API not searched), so Niche.
- **Microsoft Project**: MSPDI XML (`Project` root in `http://schemas.microsoft.com/project`) can be sniffed like an invoice and shown as a task table with a duration/Gantt summary, S–M. Binary `.mpp` is undocumented and its open reader (MPXJ) is LGPL [I]: ruled out.
- **CHM**: ITSF container with LZX compression. ChmPages is a free Mac app with a Quick Look plugin, last updated 2022-05-06 [V, VC]. An own LZX decoder is M; Niche.
- **DjVu**: IFF85-style container (JB2 bilevel, IW44 wavelets). DjVuLibre is GPL [R, [DjVuLibre](https://github.com/barak/djvulibre)]. [djvu-rs](https://docs.rs/djvu-rs) claims MIT and a clean-room implementation from the public spec, but it is Rust (a new toolchain) and another index lists a repository of the same name under GPL-3.0, so the licence is unresolved [R]. DjVu Reader Pro ($3.99) already claims Quick Look and thumbnails [VC]. A metadata-only reader (page count, size, DPI) is S but weak. Defer.
- **ZPL labels**: rendering needs a ZPL interpreter (M–L); no evidence gathered. Niche.
- **XBRL / iXBRL / SAF-T**: facts tables from XML are M–L and iXBRL needs HTML rendering. No evidence gathered.
- **Obsidian `.canvas` (JSON Canvas)**: claimed by Unfold [VC, landscape doc]; S as an outline of nodes and edges. Not distinctive.

## 6. Ruled out and why

- **`.eml`, `.emlx`, `.ics`, `.vcf`**: Apple already previews them. The Mail extension registers `com.apple.mail.email` and `com.apple.mail.emlx`; `iCal.qlgenerator` and `Contact.qlgenerator` are still listed by `qlmanage -m plugins`, and a test `.ics` thumbnail was produced [V]. Registering them would compete with the system for no gain. (An "email phishing lens" for `.eml` would have real value, but macOS sends each type to one provider and the system's Mail extension is the incumbent; flag only as a later experiment.) LDIF is plain text.
- **`.pst` / `.ost`**: libpff, the usual reader, is LGPL [R, from memory; its licence page was not opened]. The open MS-PST specification makes an own reader possible, but it is a large (L+) layered format (NDB, LTP, messaging), the files run to many gigabytes, and Outlook or other tools import them. Commercial Mac viewers exist (MacSonik, Enolsoft) [R].
- **`.mpp`**: see section 5.
- **XPS / OXPS**: ZIP + XAML fixed pages; text extraction is S–M but a drawing is M–L. Microsoft stopped installing XPS Viewer by default in Windows 10 1803, so new files are rarer [R, [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/a/8214115)]; free Mac viewers exist (Letter Opener opens XPS; several free XPS apps) [V]. Not worth a slot.
- **Publisher `.pub`, WordPerfect `.wpd`, Works `.wps`, `.lit`, legacy Visio `.vsd`**: no permissive library; the established readers (libmspub, libwpd, libvisio) are MPL/LGPL from memory [I]. Rule out; each has no system type [V].
- **OneNote `.one`**: [MS-ONESTORE] is open but large, and the sandbox cannot read the notebook's sibling files. A "files and links inside" inventory of a received `.one` attachment would be a Safety Lens angle (OneNote attachments were a phishing vector, from my knowledge), but I gathered no evidence; unevaluated.
- **Factur-X / ZUGFeRD *PDF* invoices**: `com.adobe.pdf` is Apple's.
- **Plain-text accounting (Ledger, hledger, Beancount), GnuCash**: already plain text; incremental value low.
- **Zotero / EndNote libraries**: SQLite; the existing SQLite presentation applies. **Notion / Roam / Logseq exports**: Markdown/CSV/JSON. **TextBundle / TextPack**: claimed by Markdown Preview (Anybox) and QLMarkdown [VC, landscape doc].
- **Scrivener `.scriv`, OmniOutliner, OmniGraffle**: vendor-owned packages; their apps likely ship their own previews (unverified).
- **Japanese Ichitaro `.jtd`, DocuWorks `.xdw`, Chinese CAJ/NH/KDH, UOF, WPS `.et`/`.dps`**: no system types [V]; no spec, licence or demand research done, so unevaluated.

## 7. Sources

Local checks, all on this Mac (macOS 27.2): `pluginkit -mAv -p com.apple.quicklook.preview`; `qlmanage -m plugins`; `mdls -name kMDItemContentType`; `qlmanage -t` on sample EPS, EML, ICS, XML, MSG and OFD files; `Info.plist` of `OFD_Preview.appex`, `OFD_Thumbnail.appex`, `MailQuickLookExtension.appex`, `QLPreviewGenerationExtension.appex`; `CoreTypes.bundle` declaration of `public.ofd`.

Mandates and e-invoicing

- [BMF FAQ: E-Rechnung ab 2025](https://www.bundesfinanzministerium.de/Content/DE/FAQ/e-rechnung.html) [R]
- [BMF letter 2025-10-15 (PDF)](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/Umsatzsteuer-Anwendungserlass/2025-10-15-einfuehrung-obligatorische-e-rechnung.pdf?__blob=publicationFile&v=3) [R]
- [economie.gouv.fr: facturation électronique](https://www.economie.gouv.fr/tout-savoir-sur-la-facturation-electronique-pour-les-entreprises) [R]
- [impots.gouv.fr: practical guide (PDF)](https://www.impots.gouv.fr/sites/default/files/media/1_metier/2_professionnel/EV/2_gestion/290_facturation_electronique/guide_pratique_facturation_electronique.pdf) [R]
- [KSeF scope](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/zakres-obowiazkowego-ksef/) [R]; [Gov.pl KAS KSeF page](https://www.gov.pl/web/kas/obowiazkowy-ksef-odroczony-do-1-lutego-2026-r) [V]
- [European Commission: VAT in the Digital Age](https://taxation-customs.ec.europa.eu/taxation/vat/vat-digital-age-vida_en) [V]
- [Forvis Mazars: Belgium](https://www.forvismazars.com/be/en/insights/newsletters-client-alerts/newsletters/mandatory-b2b-e-invoicing-in-belgium) [R, vendor]
- [Peppol BIS Billing 3.0 CustomizationID](https://docs.peppol.eu/poacc/billing/3.0/syntax/ubl-invoice/cbc-CustomizationID/) [V]
- [gruender.de: E-Rechnung empfangen](https://www.gruender.de/buchhaltung/e-rechnung-empfangen-2025/) [R]
- [pmi.it: fattura elettronica](https://www.pmi.it/impresa/contabilita-e-fisco/307732/fattura-elettronica-bilanci-roadmap-e-novita-da-luglio.html) [R]
- Turkey: [Ideasoft](https://www.ideasoft.com.tr/e-ticaret-icin-e-fatura-zorunlulugu/), [Faturaport](https://faturaport.com/blog/e-fatura/1-temmuz-2026-e-fatura-zorunlulugu-gecis-limitleri), [muhasebetr.com on XSLT](https://www.muhasebetr.com/yazarlarimiz/erhanselim/016), [Logo e-Fatura XSLT editor (PDF)](https://docs.logo.com.tr/download/attachments/50679821/E-Fatura_Xslt_Editor.pdf?api=v2) [R]
- China: [State Taxation Administration notice](https://fgk.chinatax.gov.cn/zcfgk/c100012/c5236067/content.html) [R]
- Indonesia: [DDTC on Coretax XML](https://news.ddtc.co.id/berita/nasional/1808220/coretax-diperbarui-pkp-bisa-unggah-1000-faktur-pajak-per-file-xml) [R]
- Banking: [Commerzbank EBICS 3.7](https://www.commerzbank.de/service/umstellung-von-mt-formaten-auf-camt-formate-in-ebics/), [UniCredit camt guide](https://gtgdownload.unicreditgroup.de/QG_UC_eBanking_prime_camt_DE.pdf), [DATEV](https://www.datev.de/web/de/berufsgruppenuebergreifend/gesetzliche-themen/payment/kontoumsaetze-bereitstellen-neues-format) [R]

Specifications and parsing

- [Hancom HWP 5.0 spec rev 1.3 (PDF)](https://cdn.hancom.com/link/docs/한글문서파일형식_5.0_revision1.3.pdf) [V]; [PRONOM entry](https://www.nationalarchives.gov.uk/pronom/fmt/1084) [R]
- [MS-OXMSG](https://msopenspecs.microsoft.com/files/MS-OXMSG/%5bMS-OXMSG%5d-210422.docx), [MS-OXTNEF](https://msopenspecs.microsoft.com/files/MS-OXTNEF/%5bMS-OXTNEF%5d-240820.docx), [MS-OXCMSG](https://msopenspecs.microsoft.com/files/MS-OXCMSG/%5bMS-OXCMSG%5d-230815.docx) [R: IP notice read through search summaries]
- [Visio file format reference](https://learn.microsoft.com/en-us/office/client-developer/visio/visio-file-format-reference), [Library of Congress VSDX](https://loc.gov/preservation/digital/formats/fdd/fdd000021.shtml) [R]
- Apple Security `CMSDecoder`: [overview](https://developer.apple.com/documentation/security/cmsdecoder.md), [CopyContent](https://developer.apple.com/documentation/security/cmsdecodercopycontent(_:_:).md), [CopySignerCert](https://developer.apple.com/documentation/security/cmsdecodercopysignercert(_:_:_:).md), [FinalizeMessage](https://developer.apple.com/documentation/security/cmsdecoderfinalizemessage(_:).md) [R]
- ASiC / BDOC: [id.ee](https://www.id.ee/en/article/what-is-the-difference-between-digitally-signed-documents-with-bdoc-and-asice-extensions/), [DigiDoc4 on the Mac App Store](https://apps.apple.com/us/app/digidoc4/id1370791134?mt=12) [R]
- XMind: [FileInfo](https://fileinfo.com/extension/xmind), [XMind Open plugin](https://www.obsidianstats.com/plugins/xmind-open) [R]
- HWPX structure: [GeekNews thread](https://news.hada.io/topic?id=19448) [R]
- Kindle: [heise](https://heise.de/-10281763), [Android Authority](https://www.androidauthority.com/kindle-download-tool-3526576/) [R]
- DjVu: [djvu-rs](https://docs.rs/djvu-rs), [DjVuLibre](https://github.com/barak/djvulibre) [R]
- PostScript: [TidBITS 2022](https://tidbits.com/2022/10/27/preview-in-ventura-drops-support-for-postscript-and-encapsulated-postscript-files/), [Eclectic Light 2023](https://eclecticlight.co/2023/09/25/postscripts-sudden-death-in-sonoma/), [Adobe community thread](https://community.adobe.com/t5/illustrator-discussions/mac-preview-icon-not-working-with-adobe-illustrator-eps-files/m-p/14660528/highlight/true), [EPS Preview blog](https://ameblo.jp/mymacsoftware/entry-12975288316.html) [R]
- XPS: [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/a/8214115) [R]
- Poedit: [NEWS](https://sources.debian.org/src/poedit/3.9-2/NEWS) [R]; XLIFF viewer request: [ProZ](https://mac.proz.com/forum/cat_tools_technical_help/354670-is_there_a_free_xliff_viewer_that_has_these_features.html) [R]
- mbox and PST: [MBOX Viewer search results](https://mwm.ai/apps/mbox-viewer-email-file-reader/6760871775), [MacSonik on AppSource](https://appsource.microsoft.com/en-hk/product/saas/macsonik.macsonik-pst-viewer-for-mac) [R]

Competitor app pages (App Store text via the iTunes lookup API, US storefront, 2026-10-13) [V for the quoted facts, VC for the claims]

- [P7M, XML & EU Invoice Viewer (Eutopix Labs)](https://apps.apple.com/us/app/p7m-xml-eu-invoice-viewer/id6793142246?uo=4), [eInvoice Viewer (Vogelbusch & Co)](https://apps.apple.com/us/app/einvoice-viewer/id6738959264?uo=4), [P7M Converter (Alvicore)](https://apps.apple.com/us/app/p7m-converter/id6761845334?uo=4)
- [Winmail Viewer - Letter Opener](https://apps.apple.com/us/app/winmail-viewer-letter-opener/id411897373?uo=4), [Winmail Viewer - TNEF Opener](https://apps.apple.com/us/app/winmail-viewer-tnef-opener/id6789357496?uo=4), [MSG Viewer - Email Opener](https://apps.apple.com/us/app/msg-viewer-email-opener/id6758084152?uo=4), [Msg Viewer Pro](https://apps.apple.com/us/app/msg-viewer-pro/id1019539949?uo=4)
- [HWP Viewer - Hangul hwp·hwpx](https://apps.apple.com/us/app/hwp-viewer-hangul-hwp-hwpx/id6819025696?uo=4)
- ChmPages (id1164062917), DjVu Reader Pro (id895264364), MindPreview Lite (id661760093), Quick Preview: Folder Preview (id6762034949), VSD Viewer for Visio Drawings (id580788158), Xliff Editor (id1054842874), found through the Search API

Repository documents: [competitor landscape](../2026-10-05-competitor-landscape.md), [unique feature opportunities](../2026-10-05-unique-feature-opportunities.md), `docs/decisions/012-safety-findings.md`, `docs/decisions/025-competitor-parity-program.md`, `docs/decisions/028-no-cad-in-version-1.md`, `AGENTS.md`.
