import Foundation
import PreviewContracts

/// Dynamic scripting languages and the functional languages that read like them.
extension SourceLanguageProfiles {
    static func scriptingLanguages() -> [SourceLanguageID: SourceLanguageProfile] {
        var result: [SourceLanguageID: SourceLanguageProfile] = [:]
        let line = CFamilySyntax.lineAndBlock.lines
        let block = CFamilySyntax.lineAndBlock.blocks
        let jsKeywords = "async await break case catch class const continue debugger default delete do else export extends finally for from function get if import in instanceof let new of return set static super switch this throw try typeof var void while with yield as"
        let jsTypes = "Array Object String Number Boolean Symbol Map Set WeakMap WeakSet Promise Date RegExp Error JSON Math BigInt Function"
        let jsStrings = [StringForm("\""), StringForm("'"), StringForm("`", multiline: true)]
        result[.javascript] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: jsStrings, keywords: jsKeywords, types: jsTypes,
            literals: "true false null undefined NaN Infinity", capitalizedTypes: true, decorators: true, identifierExtras: "$")
        result[.typescript] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: jsStrings,
            keywords: jsKeywords + " abstract asserts declare enum implements interface is keyof module namespace override private protected public readonly satisfies type unique infer",
            types: jsTypes + " any unknown never void string number boolean object symbol bigint",
            literals: "true false null undefined NaN Infinity", capitalizedTypes: true, decorators: true, identifierExtras: "$")
        result[.python] = SourceLanguageProfile(
            lineComments: [LineComment("#")],
            strings: [StringForm("\"\"\"", multiline: true), StringForm("'''", multiline: true), StringForm("\""), StringForm("'")],
            keywords: "and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case type",
            types: "int float str bool bytes list dict set tuple frozenset object type complex bytearray range",
            literals: "True False None", capitalizedTypes: true, decorators: true, stringPrefixes: "r u b f br rb fr rf")
        result[.ruby] = SourceLanguageProfile(
            lineComments: [LineComment("#")], blockComments: [BlockComment("=begin", "=end", lineStartOnly: true)],
            strings: [StringForm("\"", multiline: true), StringForm("'", multiline: true), StringForm("`", multiline: true)],
            keywords: "BEGIN END alias and begin break case class def defined do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require require_relative include extend attr_accessor attr_reader attr_writer private protected public raise puts lambda proc loop",
            literals: "true false nil", capitalizedTypes: true, identifierExtras: "?!", variableSigils: "@$")
        result[.php] = SourceLanguageProfile(
            lineComments: [LineComment("//"), LineComment("#")], blockComments: block,
            strings: [StringForm("'", multiline: true), StringForm("\"", multiline: true)],
            keywords: "abstract and array as break callable case catch class clone const continue declare default die do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile eval exit extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield enum",
            types: "int float string bool array object mixed void iterable callable never self parent",
            literals: "true false null", caseInsensitive: true, variableSigils: "$")
        result[.perl] = SourceLanguageProfile(
            lineComments: [LineComment("#")],
            blockComments: ["=pod", "=head1", "=head2", "=begin", "=over", "=item", "=encoding"].map { BlockComment($0, "=cut", lineStartOnly: true) },
            strings: [StringForm("'", multiline: true), StringForm("\"", multiline: true), StringForm("`", multiline: true)],
            keywords: "and cmp continue do else elsif eq exp for foreach ge goto gt if last le lt local my ne next no not or our package qq qr qw qx redo require return sub unless until use while xor print say BEGIN END die warn defined delete each exists keys values push pop shift unshift splice map grep sort reverse join split lc uc length open close eval ref bless",
            literals: "", variableSigils: "$@")
        result[.lua] = SourceLanguageProfile(
            lineComments: [LineComment("--")], strings: [StringForm("\""), StringForm("'")],
            keywords: "and break do else elseif end for function goto if in local not or repeat return then until while",
            literals: "true false nil", longBrackets: true, allowsUnderscoreInNumbers: false)
        result[.r] = SourceLanguageProfile(
            lineComments: [LineComment("#")], strings: [StringForm("\"", multiline: true), StringForm("'", multiline: true)],
            keywords: "if else repeat while function for next break in return library require",
            types: "numeric character logical integer double complex list vector matrix factor",
            literals: "TRUE FALSE NULL NA Inf NaN NA_integer_ NA_real_ NA_character_", identifierExtras: ".")
        result[.julia] = SourceLanguageProfile(
            lineComments: [LineComment("#")], blockComments: [BlockComment("#=", "=#", nests: true)],
            strings: [StringForm("\"\"\"", multiline: true), StringForm("\""), StringForm("'", character: true)],
            keywords: "abstract baremodule begin break catch const continue do else elseif end export finally for function global if import let local macro module mutable primitive quote return struct try using where while in isa",
            types: "Int Int8 Int16 Int32 Int64 UInt Float32 Float64 Bool String Char Any Nothing Vector Array Dict Set Tuple Union",
            literals: "true false nothing missing NaN Inf", capitalizedTypes: true, identifierExtras: "!")
        result[.coffeeScript] = SourceLanguageProfile(
            lineComments: [LineComment("#")], blockComments: [BlockComment("###", "###")],
            strings: [StringForm("'''", multiline: true), StringForm("\"\"\"", multiline: true), StringForm("\"", multiline: true), StringForm("'", multiline: true)],
            keywords: "and by class do else extends for if in is isnt loop new not of or return super switch then this throw try typeof unless until when while catch finally break continue delete instanceof",
            literals: "true false null undefined yes no on off", capitalizedTypes: true, identifierExtras: "$")
        result[.awk] = SourceLanguageProfile(
            lineComments: [LineComment("#")], strings: [StringForm("\"")],
            keywords: "BEGIN END function if else while for do break continue next nextfile exit return getline delete in printf print",
            types: "length substr index split sub gsub match sprintf sin cos atan2 exp log sqrt int rand srand tolower toupper system close NR NF FS OFS RS ORS FNR FILENAME",
            literals: "", variableSigils: "$")

        // Functional languages.
        result[.haskell] = SourceLanguageProfile(
            lineComments: [LineComment("--", notBeforeSymbol: true)], blockComments: [BlockComment("{-", "-}", nests: true)],
            strings: [StringForm("\""), StringForm("'", character: true)],
            keywords: "case class data default deriving do else foreign if import in infix infixl infixr instance let module newtype of then type where forall qualified as hiding mdo rec proc",
            literals: "True False", capitalizedTypes: true, identifierExtras: "'")
        result[.ocaml] = SourceLanguageProfile(
            blockComments: [BlockComment("(*", "*)", nests: true)],
            strings: [StringForm("\"", multiline: true), StringForm("'", character: true)],
            keywords: "and as assert asr begin class constraint do done downto else end exception external for fun function functor if in include inherit initializer land lazy let lor lsl lsr lxor match method mod module mutable new nonrec object of open or private rec sig struct then to try type val virtual when while with",
            types: "int float bool char string unit list array option ref exn", literals: "true false", identifierExtras: "'")
        result[.elixir] = SourceLanguageProfile(
            lineComments: [LineComment("#")],
            strings: [StringForm("\"\"\"", multiline: true), StringForm("'''", multiline: true), StringForm("\"", multiline: true), StringForm("'")],
            keywords: "after alias and case catch cond def defdelegate defexception defguard defimpl defmacro defmodule defoverridable defp defprotocol defstruct do else end fn for if import in not or quote raise receive require rescue reraise return super throw try unless unquote use when with",
            literals: "true false nil", capitalizedTypes: true, decorators: true, identifierExtras: "?!")
        result[.erlang] = SourceLanguageProfile(
            lineComments: [LineComment("%")], strings: [StringForm("\"", multiline: true)],
            keywords: "after and andalso band begin bnot bor bsl bsr bxor case catch cond div end fun if let not of or orelse receive rem try when xor",
            literals: "true false")
        result[.elm] = SourceLanguageProfile(
            lineComments: [LineComment("--", notBeforeSymbol: true)], blockComments: [BlockComment("{-", "-}", nests: true)],
            strings: [StringForm("\"\"\"", multiline: true), StringForm("\""), StringForm("'", character: true)],
            keywords: "as case else exposing if import in let module of port then type where alias",
            literals: "True False", capitalizedTypes: true, identifierExtras: "'")
        let lispIdentifier = "-?!*<>=+/.:'"
        result[.clojure] = SourceLanguageProfile(
            lineComments: [LineComment(";")], strings: [StringForm("\"", multiline: true)],
            keywords: "def defn defn- defmacro defmulti defmethod defprotocol defrecord deftype defonce fn let letfn if if-let if-not when when-let when-not cond condp case do loop recur for doseq dotimes while try catch finally throw quote var ns require import use refer in-ns and or not",
            literals: "true false nil", identifierExtras: lispIdentifier, operators: "")
        result[.lisp] = SourceLanguageProfile(
            lineComments: [LineComment(";")], blockComments: [BlockComment("#|", "|#", nests: true)],
            strings: [StringForm("\"", multiline: true)],
            keywords: "define define-syntax lambda let let* letrec if cond case else do begin quote quasiquote set! and or not defun defmacro defvar defparameter defconstant defstruct defclass defgeneric defmethod progn when unless loop dolist dotimes setq setf require provide module import export",
            literals: "t nil #t #f true false", identifierExtras: lispIdentifier, operators: "")
        return result
    }
}
