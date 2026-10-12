import Foundation
import PreviewContracts

/// Systems and application languages with C-like or Pascal-like lexical structure.
extension SourceLanguageProfiles {
    static func compiledLanguages() -> [SourceLanguageID: SourceLanguageProfile] {
        let cKeywords = "auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while _Alignas _Alignof _Atomic _Generic _Noreturn _Static_assert _Thread_local asm"
        let cTypes = "void char short int long float double signed unsigned bool size_t ssize_t ptrdiff_t intptr_t uintptr_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t FILE wchar_t _Bool _Complex"
        let cppKeywords = cKeywords + " alignas alignof and and_eq bitand bitor catch class compl concept consteval constexpr constinit const_cast co_await co_return co_yield decltype delete dynamic_cast explicit export final friend mutable namespace new noexcept not not_eq operator or or_eq override private protected public reinterpret_cast requires static_assert static_cast template this thread_local throw try typeid typename using virtual xor xor_eq"
        let cppTypes = cTypes + " char8_t char16_t char32_t string vector map set unique_ptr shared_ptr optional variant array"
        let objcKeywords = cppKeywords + " self super in out inout bycopy byref oneway"
        let line = CFamilySyntax.lineAndBlock.lines
        let block = CFamilySyntax.lineAndBlock.blocks
        let javaKeywords = "abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while var record sealed permits yield module requires exports opens uses provides"
        let c = SourceLanguageProfile(lineComments: line, blockComments: block, strings: CFamilySyntax.plainStrings,
                                      keywords: cKeywords, types: cTypes, literals: "true false NULL", preprocessor: .hashAtLineStart)
        let cpp = SourceLanguageProfile(lineComments: line, blockComments: block,
                                        strings: [StringForm("\""), StringForm("'", character: true)],
                                        keywords: cppKeywords, types: cppTypes, literals: "true false NULL nullptr", preprocessor: .hashAtLineStart)
        let objc = SourceLanguageProfile(lineComments: line, blockComments: block,
                                         strings: [StringForm("@\""), StringForm("\""), StringForm("'", character: true)],
                                         keywords: objcKeywords, types: cppTypes + " id SEL Class BOOL IMP instancetype",
                                         literals: "true false NULL nil Nil YES NO", capitalizedTypes: true,
                                         preprocessor: .hashAtLineStart, decorators: true)
        return [
            .c: c,
            .cpp: cpp,
            .objectiveC: objc,
            .objectiveCpp: objc,
            .csharp: SourceLanguageProfile(
                lineComments: line, blockComments: block,
                strings: [StringForm("\"\"\"", escape: nil, multiline: true), StringForm("$@\"", escape: nil, doubledQuote: true, multiline: true),
                          StringForm("@$\"", escape: nil, doubledQuote: true, multiline: true), StringForm("@\"", escape: nil, doubledQuote: true, multiline: true),
                          StringForm("$\""), StringForm("\""), StringForm("'", character: true)],
                keywords: "abstract as base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected public readonly ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using virtual volatile while add alias ascending async await by descending dynamic equals from get global group init into join let nameof on orderby partial record remove required scoped select set unmanaged value var when where with yield",
                types: "bool byte char decimal double float int long object sbyte short string uint ulong ushort void nint nuint",
                literals: "true false null", capitalizedTypes: true, preprocessor: .hashAtLineStart),
            .fsharp: SourceLanguageProfile(
                lineComments: [LineComment("//")], blockComments: [BlockComment("(*", "*)", nests: true)],
                strings: [StringForm("\"\"\"", escape: nil, multiline: true), StringForm("@\"", escape: nil, doubledQuote: true, multiline: true),
                          StringForm("\"", multiline: true), StringForm("'", character: true)],
                keywords: "abstract and as assert base begin class default delegate do done downcast downto elif else end exception extern finally fixed for fun function global if in inherit inline interface internal lazy let match member module mutable namespace new not of open or override private public rec return select sig static struct then to try type upcast use val void when while with yield",
                types: "int int64 byte float double string bool char unit obj decimal sbyte uint32 uint64 option list seq array",
                literals: "true false null", capitalizedTypes: true, preprocessor: .hashAtLineStart, identifierExtras: "'"),
            .visualBasic: SourceLanguageProfile(
                lineComments: [LineComment("'"), LineComment("REM"), LineComment("Rem"), LineComment("rem")],
                strings: [StringForm("\"", escape: nil, doubledQuote: true)],
                keywords: "addhandler addressof alias and andalso as byref byval call case catch class const continue declare default delegate dim directcast do each else elseif end endif enum erase error event exit finally for friend function get gettype global gosub goto handles if implements imports in inherits interface is isnot let lib like loop me mod module mustinherit mustoverride mybase myclass namespace narrowing new next not nothing notinheritable notoverridable of on operator option optional or orelse overloads overridable overrides paramarray partial private property protected public raiseevent readonly redim removehandler resume return select set shadows shared static step stop structure sub synclock then throw to try trycast typeof using wend when while widening with withevents writeonly xor",
                types: "boolean byte char date decimal double integer long object sbyte short single string uinteger ulong ushort variant",
                literals: "true false nothing", caseInsensitive: true, capitalizedTypes: false, preprocessor: .hashAtLineStart),
            .java: SourceLanguageProfile(
                lineComments: line, blockComments: block,
                strings: [StringForm("\"\"\"", multiline: true), StringForm("\""), StringForm("'", character: true)],
                keywords: javaKeywords, types: "boolean byte char double float int long short void var",
                literals: "true false null", capitalizedTypes: true, decorators: true),
            .kotlin: SourceLanguageProfile(
                lineComments: line, blockComments: [BlockComment("/*", "*/", nests: true)],
                strings: [StringForm("\"\"\"", escape: nil, multiline: true), StringForm("\""), StringForm("'", character: true)],
                keywords: "as break class continue do else for fun if in interface is object package return super this throw try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam value where abstract actual annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg",
                types: "Int Long Short Byte Float Double Boolean Char String Unit Any Nothing",
                literals: "true false null", capitalizedTypes: true, decorators: true),
            .scala: SourceLanguageProfile(
                lineComments: line, blockComments: [BlockComment("/*", "*/", nests: true)],
                strings: [StringForm("\"\"\"", escape: nil, multiline: true), StringForm("\""), StringForm("'", character: true)],
                keywords: "abstract case catch class def do else enum export extends final finally for forSome given if implicit import lazy match new object override package private protected return sealed super then throw trait try type val var while with yield opaque open transparent inline using",
                types: "Int Long Short Byte Float Double Boolean Char String Unit Any AnyRef AnyVal Nothing Null",
                literals: "true false null", capitalizedTypes: true, decorators: true),
            .groovy: SourceLanguageProfile(
                lineComments: [LineComment("//"), LineComment("#!", lineStartOnly: true)], blockComments: block,
                strings: [StringForm("'''", multiline: true), StringForm("\"\"\"", multiline: true), StringForm("\""), StringForm("'")],
                keywords: "abstract as assert break case catch class const continue def default do else enum extends final finally for goto if implements import in instanceof interface native new package private protected public return static strictfp super switch synchronized this threadsafe throw throws transient try volatile while var trait pipeline stage steps agent",
                types: "boolean byte char double float int long short void String Object List Map",
                literals: "true false null", capitalizedTypes: true, decorators: true),
            .swift: SourceLanguageProfile(
                lineComments: line, blockComments: [BlockComment("/*", "*/", nests: true)],
                strings: [StringForm("\"\"\"", multiline: true), StringForm("\"")],
                keywords: "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as await async actor consuming borrowing each get set willSet didSet is isolated macro nonisolated mutating nonmutating override required convenience final lazy weak unowned indirect optional dynamic some any try throws self super Self",
                types: "Int UInt Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64 Float Double Bool String Character Void Any AnyObject Never",
                literals: "true false nil", capitalizedTypes: true, preprocessor: .hashAnywhere, decorators: true, hashDelimitedStrings: true),
            .go: SourceLanguageProfile(
                lineComments: line, blockComments: block,
                strings: [StringForm("`", escape: nil, multiline: true), StringForm("\""), StringForm("'", character: true)],
                keywords: "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var",
                types: "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable",
                literals: "true false nil iota"),
            .rust: SourceLanguageProfile(
                lineComments: line, blockComments: [BlockComment("/*", "*/", nests: true)],
                strings: [StringForm("\"", multiline: true), StringForm("'", character: true)],
                keywords: "as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self static struct super trait type unsafe use where while abstract become box do final macro override priv try typeof unsized virtual yield union",
                types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Rc Arc Self",
                literals: "true false", capitalizedTypes: true, rustAttributes: true, stringPrefixes: "b", hashDelimitedStrings: true),
            .zig: SourceLanguageProfile(
                lineComments: [LineComment("//")],
                strings: [StringForm("\\\\", close: "\n", escape: nil, multiline: true), StringForm("\""), StringForm("'", character: true)],
                keywords: "addrspace align allowzero and anyframe anytype asm async await break callconv catch comptime const continue defer else enum errdefer error export extern fn for if inline linksection noalias noinline nosuspend opaque or orelse packed pub resume return struct suspend switch test threadlocal try union unreachable usingnamespace var volatile while",
                types: "bool void noreturn type anyerror comptime_int comptime_float u8 u16 u32 u64 u128 usize i8 i16 i32 i64 i128 isize f16 f32 f64 f128 c_int c_uint c_long c_char anyopaque",
                literals: "true false null undefined", decorators: true),
            .nim: SourceLanguageProfile(
                lineComments: [LineComment("#")], blockComments: [BlockComment("#[", "]#", nests: true)],
                strings: [StringForm("\"\"\"", escape: nil, multiline: true), StringForm("\""), StringForm("'", character: true)],
                keywords: "addr and as asm bind block break case cast concept const continue converter defer discard distinct div do elif else end enum except export finally for from func if import in include interface is isnot iterator let macro method mixin mod nil not notin object of or out proc ptr raise ref return shl shr static template try tuple type using var when while xor yield",
                types: "int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float float32 float64 bool char string cstring seq array set openArray",
                literals: "true false nil", capitalizedTypes: true),
            .crystal: SourceLanguageProfile(
                lineComments: [LineComment("#")],
                strings: [StringForm("\"", multiline: true), StringForm("'", character: true)],
                keywords: "abstract alias annotation as asm begin break case class def do else elsif end ensure enum extend for fun if in include lib macro module next of out pointerof private protected require rescue return select self sizeof struct super then type typeof uninitialized union unless until verbatim when while with yield",
                types: "Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64 Float32 Float64 Bool Char String Symbol Nil Array Hash",
                literals: "true false nil", capitalizedTypes: true, identifierExtras: "?!", variableSigils: "@"),
            .d: SourceLanguageProfile(
                lineComments: line, blockComments: [BlockComment("/*", "*/"), BlockComment("/+", "+/", nests: true)],
                strings: [StringForm("`", escape: nil, multiline: true), StringForm("\"", multiline: true), StringForm("'", character: true)],
                keywords: "abstract alias align asm assert auto body break case cast catch class const continue debug default delegate delete deprecated do else enum export extern final finally for foreach foreach_reverse function goto if immutable import in inout interface invariant is lazy mixin module new nothrow out override package pragma private protected public pure ref return scope shared static struct super switch synchronized template this throw try typeid typeof union unittest version while with",
                types: "bool byte ubyte short ushort int uint long ulong float double real char wchar dchar void string size_t",
                literals: "true false null", capitalizedTypes: true, decorators: true),
            .dart: SourceLanguageProfile(
                lineComments: line, blockComments: [BlockComment("/*", "*/", nests: true)],
                strings: [StringForm("'''", multiline: true), StringForm("\"\"\"", multiline: true), StringForm("'"), StringForm("\"")],
                keywords: "abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory final finally for Function get hide if implements import in interface is late library mixin new on operator part required rethrow return sealed set show static super switch sync this throw try typedef var void when while with yield",
                types: "int double num bool String List Map Set Object dynamic Future Stream Iterable",
                literals: "true false null", capitalizedTypes: true, decorators: true, stringPrefixes: "r"),
            .pascal: SourceLanguageProfile(
                lineComments: [LineComment("//")], blockComments: [BlockComment("{", "}"), BlockComment("(*", "*)")],
                strings: [StringForm("'", escape: nil, doubledQuote: true)],
                keywords: "and array as asm begin case class const constructor destructor div do downto else end except exports file finalization finally for function goto if implementation in inherited initialization inline interface is label library mod nil not object of on or out packed private procedure program property protected public published raise record repeat resourcestring set shl shr string then threadvar to try type unit until uses var while with xor",
                types: "integer cardinal byte word longint shortint smallint int64 boolean char real double single extended pointer",
                literals: "true false nil", caseInsensitive: true, dollarHexNumbers: true),
            .ada: SourceLanguageProfile(
                lineComments: [LineComment("--")],
                strings: [StringForm("\"", escape: nil, doubledQuote: true), StringForm("'", escape: nil, character: true)],
                keywords: "abort abs abstract accept access aliased all and array at begin body case constant declare delay delta digits do else elsif end entry exception exit for function generic goto if in interface is limited loop mod new not null of or others out overriding package parallel pragma private procedure protected raise range record rem renames requires return reverse select separate some subtype synchronized tagged task terminate then type until use when while with xor",
                types: "integer natural positive float boolean character string duration",
                literals: "true false null", caseInsensitive: true),
            .fortran: SourceLanguageProfile(
                lineComments: [LineComment("!")],
                strings: [StringForm("'", escape: nil, doubledQuote: true), StringForm("\"", escape: nil, doubledQuote: true)],
                keywords: "allocatable allocate assign associate backspace block call case close common contains continue cycle data deallocate default dimension do else elseif elsewhere end endif enddo endfile entry equivalence exit external format function goto if implicit import in include inquire intent interface intrinsic kind len module namelist nullify only open operator optional out parameter pause pointer print private procedure program public read recursive result return rewind save select sequence stop subroutine target then type use value where while write",
                types: "integer real complex character logical double precision",
                literals: "true false", caseInsensitive: true),
            .assembly: SourceLanguageProfile(
                lineComments: [LineComment(";"), LineComment("//"), LineComment("#", lineStartOnly: true)], blockComments: [BlockComment("/*", "*/")],
                strings: [StringForm("\""), StringForm("'")],
                keywords: "mov movl movq movb movw movzx movsx lea push pop call ret jmp je jne jz jnz jg jl jge jle ja jb jae jbe cmp test add sub mul imul div idiv inc dec and or xor not neg shl shr sal sar rol ror nop int syscall leave enter ldr str ldp stp bl b bx blr cbz cbnz adr adrp mrs msr cmpq addq subq ldrb strb orr eor mvn tst svc hlt cli sti xchg cdq cqo rep movs stos lods scas section segment global extern db dw dd dq resb resw resd resq equ times align",
                types: "rax rbx rcx rdx rsi rdi rsp rbp r8 r9 r10 r11 r12 r13 r14 r15 eax ebx ecx edx esi edi esp ebp ax bx cx dx al bl cl dl ah bh ch dh sp lr pc xzr wzr x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15 x16 x17 x18 x19 x20 x21 x22 x23 x24 x25 x26 x27 x28 x29 x30 w0 w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12 w13 w14 w15 w16 w17 w18 w19 w20",
                literals: "", caseInsensitive: true, dollarHexNumbers: true)
        ]
    }
}
