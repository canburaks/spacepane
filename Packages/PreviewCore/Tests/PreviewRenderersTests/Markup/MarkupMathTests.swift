import Foundation
import Testing
@testable import PreviewRenderers

@Suite("TeX math approximation")
struct MarkupMathTests {
    @Test(arguments: [
        (#"\alpha + \beta = \gamma"#, "α + β = γ"),
        (#"\Gamma \Delta \Omega \pi \varphi \phi"#, "Γ Δ Ω π φ ϕ"),
        (#"a \leq b \geq c \neq d \approx e"#, "a ≤ b ≥ c ≠ d ≈ e"),
        (#"x \in A \cup B \cap C \subset D"#, "x ∈ A ∪ B ∩ C ⊂ D"),
        (#"A \to B \Rightarrow C \leftrightarrow D"#, "A → B ⇒ C ↔ D"),
        (#"\sum_{i=1}^{n} i \cdot \infty \times 2"#, "∑ᵢ₌₁ⁿ i ⋅ ∞ × 2"),
        (#"\forall x \exists y \nabla f \partial g"#, "∀ x ∃ y ∇ f ∂ g"),
        (#"\sin x + \cos y \log z"#, "sin x + cos y log z"),
        (#"\pm 1 \mp 2"#, "± 1 ∓ 2")
    ])
    func commonSymbolsMapToUnicode(source: String, expected: String) {
        #expect(MarkupMath.approximate(source) == expected)
    }

    @Test func fractionsAndRootsUseTheFractionSlashAndRadicalSigns() {
        #expect(MarkupMath.approximate(#"\frac{a}{b}"#) == "a⁄b")
        #expect(MarkupMath.approximate(#"\frac12"#) == "1⁄2")
        #expect(MarkupMath.approximate(#"\frac{x+1}{2}"#) == "(x+1)⁄2")
        #expect(MarkupMath.approximate(#"\sqrt{x}"#) == "√x")
        #expect(MarkupMath.approximate(#"\sqrt{x+1}"#) == "√(x+1)")
        #expect(MarkupMath.approximate(#"\sqrt[3]{x}"#) == "∛x")
        #expect(MarkupMath.approximate(#"\sqrt[5]{x}"#) == "⁵√x")
        #expect(MarkupMath.approximate(#"\binom{n}{k}"#) == "C(n, k)")
    }

    @Test func scriptsUseUnicodeWhenEveryCharacterHasAFormAndFallBackVisibly() {
        #expect(MarkupMath.approximate("x^2 + y_1") == "x² + y₁")
        #expect(MarkupMath.approximate("x^{n+1}") == "xⁿ⁺¹")
        #expect(MarkupMath.approximate("a_{ij}") == "aᵢⱼ")
        #expect(MarkupMath.approximate(#"e^{i\pi}"#) == "e^(iπ)")
        #expect(MarkupMath.approximate("x^q") == "x^q")
        #expect(MarkupMath.approximate("x_{ab c}") == "x_(ab c)")
        #expect(MarkupMath.approximate("x_i^2") == "xᵢ²")
        #expect(MarkupMath.approximate("^2") == "²")
    }

    @Test func accentsFontsAndSpacingCommands() {
        #expect(MarkupMath.approximate(#"\hat{x}"#) == "x\u{0302}")
        #expect(MarkupMath.approximate(#"\vec{v}"#) == "v\u{20D7}")
        #expect(MarkupMath.approximate(#"\overline{AB}"#) == "A\u{0305}B\u{0305}")
        #expect(MarkupMath.approximate(#"\mathbb{R}^n"#) == "ℝⁿ")
        #expect(MarkupMath.approximate(#"\mathbb{Z} \mathbb{Q} \mathbb{C}"#) == "ℤ ℚ ℂ")
        #expect(MarkupMath.approximate(#"\mathrm{d}x \mathbf{v} \text{ if } x"#) == "dx v if x")
        #expect(MarkupMath.approximate(#"a\,b\;c\quad d"#) == "a\u{2009}b\u{2004}c\u{2003}d")
    }

    @Test func sizingCommandsAndEnvironmentsAreTidied() {
        #expect(MarkupMath.approximate(#"\left( \frac{a}{b} \right)"#) == "(a⁄b)")
        #expect(MarkupMath.approximate(#"\left. x \right|"#) == "x |")
        #expect(MarkupMath.approximate(#"\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}"#) == "(1, 2; 3, 4)")
        #expect(MarkupMath.approximate(#"\begin{bmatrix}1&2\\3&4\end{bmatrix}"#) == "[1, 2; 3, 4]")
        #expect(MarkupMath.approximate(#"a &= b \\ c &= d"#, multiline: true) == "a = b\nc = d")
        #expect(MarkupMath.approximate(#"a \\ b"#) == "a b")
        #expect(MarkupMath.approximate(#"x \label{eq:1} \nonumber"#) == "x")
    }

    @Test func unknownCommandsStayVisibleWithTheirArguments() {
        #expect(MarkupMath.approximate(#"\foo{bar}"#) == "\\foo{bar}")
        #expect(MarkupMath.approximate(#"\unknownsymbol + 1"#) == "\\unknownsymbol + 1")
    }

    @Test func minusSignsAndPrimesUseTypographicCharacters() {
        #expect(MarkupMath.approximate("a-b") == "a−b")
        #expect(MarkupMath.approximate("f'(x)") == "f′(x)")
    }

    @Test func malformedOrDeeplyNestedInputIsBoundedAndNeverCrashes() {
        for source in [#"\frac{"#, #"\frac{a}"#, #"x^"#, #"{{{{"#, #"}}}}"#, #"\begin{pmatrix} a"#, #"\"#, #"a_"#, #"\sqrt["#, "$"] {
            _ = MarkupMath.approximate(source)
        }
        let nested = String(repeating: "{", count: 500) + "x" + String(repeating: "}", count: 500)
        #expect(MarkupMath.approximate(nested).contains("x") || !MarkupMath.approximate(nested).isEmpty)
        let started = ContinuousClock.now
        let long = String(repeating: #"\alpha^{2}_{i} "#, count: 400) // 6,000 characters, above the 4,096 bound
        #expect(MarkupMath.approximate(long) == long)
        let atBound = String(repeating: "ab ", count: 1_300)
        _ = MarkupMath.approximate(atBound)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func approximationOfConcealedTextKeepsTheConcealmentToken() {
        #expect(MarkupMath.approximate("x = ••••") == "x = ••••")
    }

    @Test func everyLookupTableLoadsWithoutDuplicateKeys() {
        // Dictionary literals with duplicate keys trap at first use; exercising every path guards the tables.
        for source in [#"\alpha"#, "x^2", "x_1", #"\hat{x}"#, #"\mathbb{R}"#, #"\sin"#, #"\left("#, #"\leq"#] {
            #expect(!MarkupMath.approximate(source).isEmpty)
        }
    }
}

@Suite("TeX text cleanup")
struct MarkupLaTeXTextTests {
    @Test func bracesAccentsAndDashesBecomePlainText() {
        #expect(MarkupLaTeXText.plain("The {TeX}book") == "The TeXbook")
        #expect(MarkupLaTeXText.plain(#"M\"{u}ller and Schr\"odinger"#) == "Müller and Schrödinger")
        #expect(MarkupLaTeXText.plain(#"Garc\'{\i}a, \c{C}elik, \v{S}koda, \ss{} and \o"#) == "García, Çelik, Škoda, ß and ø")
        #expect(MarkupLaTeXText.plain("pages 10--20 --- and more") == "pages 10–20 — and more")
        #expect(MarkupLaTeXText.plain("``quoted'' text") == "“quoted” text")
        #expect(MarkupLaTeXText.plain(##"R\&D 50\% \$5 \#1 a\_b"##) == "R&D 50% $5 #1 a_b")
    }

    @Test func textCommandsKeepTheirArgumentAndUnknownCommandsLoseTheirName() {
        #expect(MarkupLaTeXText.plain(#"\emph{very} \textbf{bold} \texttt{mono}"#) == "very bold mono")
        #expect(MarkupLaTeXText.plain(#"\url{https://example.invalid/x} \href{https://a.invalid}{label}"#) == "https://example.invalid/x label")
        #expect(MarkupLaTeXText.plain(#"\unknowncommand{kept} text"#) == "kept text")
    }

    @Test func inlineMathIsApproximatedAndInputIsBounded() {
        #expect(MarkupLaTeXText.plain("value $x^2$ here") == "value x² here")
        #expect(MarkupLaTeXText.plain(String(repeating: "a", count: 20_000)).count == MarkupLaTeXText.maximumCharacters)
        _ = MarkupLaTeXText.plain(String(repeating: "{", count: 5_000))
    }
}
