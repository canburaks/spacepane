import Foundation
import PreviewContracts

/// Shells, command languages, hardware description languages and smart-contract languages.
extension SourceLanguageProfiles {
    static func shellLanguages() -> [SourceLanguageID: SourceLanguageProfile] {
        var result: [SourceLanguageID: SourceLanguageProfile] = [:]
        result[.shell] = SourceLanguageProfile(
            lineComments: [LineComment("#", atWordStart: true)],
            strings: [StringForm("'", escape: nil, multiline: true), StringForm("\"", multiline: true), StringForm("`", multiline: true)],
            keywords: "if then else elif fi for while until do done case esac in function select time coproc break continue return exit export local readonly declare typeset unset shift source alias echo printf cd eval exec set test trap wait read let",
            literals: "true false", variableSigils: "$", keyStyle: .immediateEquals, operators: "|&<>!")
        result[.fish] = SourceLanguageProfile(
            lineComments: [LineComment("#", atWordStart: true)],
            strings: [StringForm("'", multiline: true), StringForm("\"", multiline: true)],
            keywords: "and argparse begin break builtin case command continue else end exit for function if not or return set switch while string status test math read echo",
            literals: "true false", variableSigils: "$", operators: "|&<>!")
        result[.powerShell] = SourceLanguageProfile(
            lineComments: [LineComment("#")], blockComments: [BlockComment("<#", "#>")],
            strings: [StringForm("@\"", close: "\"@", escape: nil, multiline: true), StringForm("@'", close: "'@", escape: nil, multiline: true),
                      StringForm("'", escape: nil, doubledQuote: true), StringForm("\"", escape: "`", multiline: true)],
            keywords: "begin break catch class continue data do dynamicparam else elseif end enum exit filter finally for foreach from function if in inlinescript parallel param process return sequence switch throw trap try until using var while workflow",
            types: "string int bool double float array hashtable object pscustomobject datetime",
            literals: "", caseInsensitive: true, identifierExtras: "-", variableSigils: "$")
        result[.batch] = SourceLanguageProfile(
            lineComments: [LineComment("::", lineStartOnly: true), LineComment("REM", lineStartOnly: true), LineComment("rem", lineStartOnly: true),
                           LineComment("Rem", lineStartOnly: true)],
            strings: [StringForm("\"", escape: nil)],
            keywords: "if else for in do goto call set echo exit setlocal endlocal enabledelayedexpansion pause shift start cd md mkdir rd rmdir del copy move ren type cls title color not exist defined errorlevel equ neq lss leq gtr geq off on",
            literals: "", caseInsensitive: true, operators: "|&<>")
        result[.nushell] = SourceLanguageProfile(
            lineComments: [LineComment("#")],
            strings: [StringForm("\"", multiline: true), StringForm("'", escape: nil, multiline: true), StringForm("`", escape: nil, multiline: true)],
            keywords: "alias def def-env export extern for if else let let-env mut const loop match module overlay return source try catch use while in break continue error",
            literals: "true false null", identifierExtras: "-", variableSigils: "$")
        result[.appleScript] = SourceLanguageProfile(
            lineComments: [LineComment("--"), LineComment("#")], blockComments: [BlockComment("(*", "*)", nests: true)],
            strings: [StringForm("\"")],
            keywords: "about above after against and apart around as aside at back before beginning behind below beneath beside between but by considering contain contains continue copy count div does eighth else end equal equals error every exit fifth first for fourth from front get given global if ignoring in instead into is it its last local me middle mod my ninth not of on onto or out over prop property put ref reference repeat returning script second set seventh since sixth some tell tenth that the then third through thru timeout times to transaction try until where while whose with without",
            types: "integer real text string boolean list record date", literals: "true false missing", caseInsensitive: true)
        return result
    }

    static func hardwareLanguages() -> [SourceLanguageID: SourceLanguageProfile] {
        var result: [SourceLanguageID: SourceLanguageProfile] = [:]
        let line = CFamilySyntax.lineAndBlock.lines
        let block = CFamilySyntax.lineAndBlock.blocks
        let verilogKeywords = "always and assign automatic begin buf case casex casez cell cmos config deassign default defparam design disable edge else end endcase endconfig endfunction endgenerate endmodule endprimitive endspecify endtable endtask event for force forever fork function generate genvar if ifnone incdir include initial inout input instance integer join large liblist library localparam macromodule medium module nand negedge nmos nor not notif0 notif1 or output parameter pmos posedge primitive pull0 pull1 pulldown pullup rcmos real realtime reg release repeat rnmos rpmos rtran scalared signed small specify specparam strong0 strong1 supply0 supply1 table task time tran tri tri0 tri1 triand trior trireg unsigned use vectored wait wand weak0 weak1 while wire wor xnor xor"
        result[.vhdl] = SourceLanguageProfile(
            lineComments: [LineComment("--")],
            strings: [StringForm("\"", escape: nil, doubledQuote: true), StringForm("'", escape: nil, character: true)],
            keywords: "abs access after alias all and architecture array assert attribute begin block body buffer bus case component configuration constant disconnect downto else elsif end entity exit file for function generate generic group guarded if impure in inertial inout is label library linkage literal loop map mod nand new next nor not null of on open or others out package port postponed procedure process pure range record register reject rem report return rol ror select severity signal shared sla sll sra srl subtype then to transport type unaffected units until use variable wait when while with xnor xor",
            types: "std_logic std_logic_vector std_ulogic unsigned signed integer natural positive boolean bit bit_vector string character real time",
            literals: "true false", caseInsensitive: true)
        result[.verilog] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: [StringForm("\"")], keywords: verilogKeywords, literals: "",
            preprocessor: .backtickAtLineStart, basedNumbers: true)
        result[.systemVerilog] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: [StringForm("\"")],
            keywords: verilogKeywords + " class endclass interface endinterface package endpackage program endprogram typedef enum struct union packed unique priority return break continue virtual extends implements import export modport clocking endclocking constraint rand randc cover covergroup endgroup assert assume property endproperty sequence endsequence always_comb always_ff always_latch foreach void new this super local protected static const ref var type",
            types: "logic bit byte int shortint longint string", literals: "null", preprocessor: .backtickAtLineStart, basedNumbers: true)
        result[.solidity] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: [StringForm("\""), StringForm("'")],
            keywords: "abstract anonymous as assembly break calldata catch constant constructor continue contract delete do else emit enum error event external fallback for function if immutable import indexed interface internal is library mapping memory modifier new override payable pragma private public pure receive return returns storage struct super this throw try type unchecked using view virtual while",
            types: "address bool string bytes byte int uint int8 int16 int32 int64 int128 int256 uint8 uint16 uint32 uint64 uint128 uint256 bytes1 bytes2 bytes4 bytes8 bytes16 bytes32 fixed ufixed",
            literals: "true false", capitalizedTypes: true)
        return result
    }

    static func queryLanguages() -> [SourceLanguageID: SourceLanguageProfile] {
        var result: [SourceLanguageID: SourceLanguageProfile] = [:]
        let line = CFamilySyntax.lineAndBlock.lines
        let block = CFamilySyntax.lineAndBlock.blocks
        result[.sql] = SourceLanguageProfile(
            lineComments: [LineComment("--")], blockComments: [BlockComment("/*", "*/")],
            strings: [StringForm("'", escape: nil, doubledQuote: true, multiline: true),
                      StringForm("\"", escape: nil, doubledQuote: true, role: .key), StringForm("`", escape: nil, doubledQuote: true, role: .key)],
            keywords: "select from where and or not in is like between exists insert into values update set delete create alter drop table index view database schema primary key foreign references unique default check constraint join inner left right full outer cross on group by order having limit offset union all distinct as case when then else end begin commit rollback transaction grant revoke with recursive returning using natural asc desc over partition truncate explain analyze pragma if replace trigger function procedure declare cursor fetch for each row execute call return returns language",
            types: "int integer bigint smallint tinyint serial bigserial decimal numeric float real double precision boolean bool char varchar text blob date time timestamp timestamptz datetime interval json jsonb uuid bytea binary varbinary money",
            literals: "true false null", caseInsensitive: true)
        result[.graphQL] = SourceLanguageProfile(
            lineComments: [LineComment("#")],
            strings: [StringForm("\"\"\"", escape: nil, multiline: true), StringForm("\"")],
            keywords: "query mutation subscription fragment on type interface union enum input extend schema directive scalar implements repeatable",
            types: "Int Float String Boolean ID", literals: "true false null", capitalizedTypes: true, decorators: true, variableSigils: "$")
        result[.protobuf] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: [StringForm("\""), StringForm("'")],
            keywords: "syntax package import weak public option message enum service rpc returns stream oneof map repeated optional required reserved extensions extend group to max",
            types: "double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes",
            literals: "true false inf nan", capitalizedTypes: true)
        result[.thrift] = SourceLanguageProfile(
            lineComments: [LineComment("//"), LineComment("#")], blockComments: block, strings: [StringForm("\""), StringForm("'")],
            keywords: "namespace include cpp_include typedef const enum struct union exception service extends oneway throws required optional void senum",
            types: "bool byte i8 i16 i32 i64 double string binary list set map", literals: "true false")
        result[.prisma] = SourceLanguageProfile(
            lineComments: [LineComment("//")], strings: [StringForm("\"")],
            keywords: "model enum datasource generator type view",
            types: "String Int Float Boolean DateTime Json Decimal BigInt Bytes Unsupported",
            literals: "true false null", capitalizedTypes: true, decorators: true)
        return result
    }
}
