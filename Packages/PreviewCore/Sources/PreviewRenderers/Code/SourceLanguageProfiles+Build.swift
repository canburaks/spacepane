import Foundation
import PreviewContracts

/// Build, infrastructure and configuration languages, web languages and shader languages.
extension SourceLanguageProfiles {
    static func buildLanguages() -> [SourceLanguageID: SourceLanguageProfile] {
        var result: [SourceLanguageID: SourceLanguageProfile] = [:]
        let block = CFamilySyntax.lineAndBlock.blocks
        result[.hcl] = SourceLanguageProfile(
            lineComments: [LineComment("#"), LineComment("//")], blockComments: block, strings: [StringForm("\"")],
            keywords: "resource variable output module data provider locals terraform for for_each count dynamic depends_on lifecycle provisioner connection backend required_providers required_version if in else",
            types: "string number bool list map set object tuple any", literals: "true false null",
            identifierExtras: "-", keyStyle: .spacedEquals)
        result[.nix] = SourceLanguageProfile(
            lineComments: [LineComment("#")], blockComments: [BlockComment("/*", "*/")],
            strings: [StringForm("''", escape: nil, multiline: true), StringForm("\"", multiline: true)],
            keywords: "assert else if in inherit import let or rec then with", literals: "true false null",
            identifierExtras: "-'", keyStyle: .spacedEquals)
        result[.starlark] = SourceLanguageProfile(
            lineComments: [LineComment("#")],
            strings: [StringForm("\"\"\"", multiline: true), StringForm("'''", multiline: true), StringForm("\""), StringForm("'")],
            keywords: "and break continue def elif else for if in lambda load not or pass return while",
            literals: "True False None", keyStyle: .spacedEquals, stringPrefixes: "r b")
        result[.cmake] = SourceLanguageProfile(
            lineComments: [LineComment("#")], blockComments: [BlockComment("#[[", "]]")], strings: [StringForm("\"", multiline: true)],
            keywords: "if elseif else endif foreach endforeach while endwhile function endfunction macro endmacro block endblock return break continue set unset option project cmake_minimum_required add_executable add_library add_subdirectory add_custom_command add_custom_target add_definitions add_compile_options add_dependencies target_link_libraries target_include_directories target_compile_definitions target_compile_options target_sources find_package find_library find_path find_program include include_directories link_directories install file string list message math configure_file execute_process enable_testing add_test set_target_properties set_property get_property get_target_property aux_source_directory try_compile",
            literals: "ON OFF TRUE FALSE YES NO", caseInsensitive: true, operators: "")
        result[.meson] = SourceLanguageProfile(
            lineComments: [LineComment("#")], strings: [StringForm("'''", multiline: true), StringForm("'")],
            keywords: "if elif else endif foreach endforeach break continue and or not in project executable library shared_library static_library dependency declare_dependency subdir include_directories files configure_file install_headers custom_target run_command get_option",
            literals: "true false", keyStyle: .declarationColon)
        result[.makefile] = SourceLanguageProfile(
            lineComments: [LineComment("#")], strings: [StringForm("\""), StringForm("'")],
            keywords: "ifeq ifneq ifdef ifndef else endif include sinclude define endef export unexport override vpath private undefine",
            literals: "", variableSigils: "$", keyStyle: .spacedEquals)
        result[.dockerfile] = SourceLanguageProfile(
            lineComments: [LineComment("#", lineStartOnly: true)], strings: [StringForm("\""), StringForm("'")],
            keywords: "from run cmd label maintainer expose env add copy entrypoint volume user workdir arg onbuild stopsignal healthcheck shell as",
            literals: "", caseInsensitive: true, variableSigils: "$", keyStyle: .immediateEquals)
        result[.just] = SourceLanguageProfile(
            lineComments: [LineComment("#")], strings: [StringForm("\"\"\"", multiline: true), StringForm("\""), StringForm("'", escape: nil)],
            keywords: "set export alias import mod if else", literals: "true false", keyStyle: .spacedEquals)
        result[.jsonnet] = SourceLanguageProfile(
            lineComments: [LineComment("//"), LineComment("#")], blockComments: [BlockComment("/*", "*/")],
            strings: [StringForm("|||", escape: nil, multiline: true), StringForm("\""), StringForm("'")],
            keywords: "assert else error for function if import importstr importbin in local self super tailstrict then",
            literals: "true false null", keyStyle: .declarationColon)
        result[.plantUML] = SourceLanguageProfile(
            lineComments: [LineComment("'")], blockComments: [BlockComment("/'", "'/")], strings: [StringForm("\"")],
            keywords: "actor participant usecase class interface abstract enum component node database queue note end title skinparam package namespace activate deactivate alt else opt loop par group box autonumber legend endlegend hide show left right top bottom of over as start stop if then endif while endwhile fork repeat return",
            literals: "", decorators: true)
        result[.ignoreList] = SourceLanguageProfile(
            lineComments: [LineComment("#", lineStartOnly: true)], literals: "", operators: "!")
        return result
    }

    static func webLanguages() -> [SourceLanguageID: SourceLanguageProfile] {
        var result: [SourceLanguageID: SourceLanguageProfile] = [:]
        let html = SourceLanguageProfile(markup: .html)
        let template = SourceLanguageProfile(markup: .template)
        result[.html] = html
        result[.vue] = template
        result[.svelte] = template
        result[.astro] = template
        result[.template] = template
        let css = SourceLanguageProfile(
            blockComments: [BlockComment("/*", "*/")], strings: [StringForm("\""), StringForm("'")],
            literals: "inherit initial unset none auto", decorators: true, identifierExtras: "-", keyStyle: .declarationColon, operators: "")
        result[.css] = css
        let scss = SourceLanguageProfile(
            lineComments: [LineComment("//")], blockComments: [BlockComment("/*", "*/")], strings: [StringForm("\""), StringForm("'")],
            literals: "inherit initial unset none auto true false null", decorators: true, identifierExtras: "-", variableSigils: "$",
            keyStyle: .declarationColon, operators: "")
        result[.scss] = scss
        result[.sass] = scss
        result[.less] = scss
        result[.stylus] = scss
        result[.pug] = SourceLanguageProfile(
            lineComments: [LineComment("//")], strings: [StringForm("\""), StringForm("'")],
            keywords: "mixin include extends block if else each while case when default for in unless doctype", literals: "true false null",
            identifierExtras: "-", operators: "")
        return result
    }

    static func shaderLanguages() -> [SourceLanguageID: SourceLanguageProfile] {
        var result: [SourceLanguageID: SourceLanguageProfile] = [:]
        let line = CFamilySyntax.lineAndBlock.lines
        let block = CFamilySyntax.lineAndBlock.blocks
        let common = "break continue do for while switch case default if else return discard struct const static in out inout uniform"
        result[.glsl] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: [StringForm("\"")],
            keywords: common + " attribute varying buffer shared coherent volatile restrict readonly writeonly layout centroid flat smooth noperspective patch sample subroutine precision highp mediump lowp",
            types: "void bool int uint float double vec2 vec3 vec4 ivec2 ivec3 ivec4 uvec2 uvec3 uvec4 bvec2 bvec3 bvec4 dvec2 dvec3 dvec4 mat2 mat3 mat4 mat2x2 mat3x3 mat4x4 sampler1D sampler2D sampler3D samplerCube sampler2DArray",
            literals: "true false", preprocessor: .hashAtLineStart)
        result[.hlsl] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: [StringForm("\"")],
            keywords: common + " cbuffer tbuffer class interface namespace typedef extern inline groupshared row_major column_major register packoffset technique pass",
            types: "void bool int uint half float double float2 float3 float4 half2 half3 half4 int2 int3 int4 uint2 uint3 uint4 float2x2 float3x3 float4x4 Texture2D Texture3D TextureCube SamplerState RWTexture2D StructuredBuffer RWStructuredBuffer",
            literals: "true false", preprocessor: .hashAtLineStart)
        result[.metal] = SourceLanguageProfile(
            lineComments: line, blockComments: block, strings: [StringForm("\"")],
            keywords: common + " kernel vertex fragment constant device threadgroup thread using namespace template typename enum class public private",
            types: "void bool char uchar short ushort int uint long ulong half float half2 half3 half4 float2 float3 float4 int2 int3 int4 uint2 uint3 uint4 float2x2 float3x3 float4x4 half4x4 texture2d texture3d texturecube sampler",
            literals: "true false nullptr", preprocessor: .hashAtLineStart, decorators: true)
        result[.wgsl] = SourceLanguageProfile(
            lineComments: line, blockComments: [BlockComment("/*", "*/", nests: true)],
            keywords: "fn let var const struct if else for while loop return break continue switch case default discard override alias enable requires",
            types: "f32 f16 i32 u32 bool vec2 vec3 vec4 mat2x2 mat3x3 mat4x4 array texture_2d texture_3d texture_cube sampler ptr atomic",
            literals: "true false", decorators: true)
        result[.webAssemblyText] = SourceLanguageProfile(
            lineComments: [LineComment(";;")], blockComments: [BlockComment("(;", ";)", nests: true)], strings: [StringForm("\"")],
            keywords: "module func param result local global memory table elem data type import export start call call_indirect block loop if else end br br_if br_table return unreachable nop drop select then mut offset",
            types: "i32 i64 f32 f64 v128 funcref externref", literals: "", identifierExtras: ".", variableSigils: "$", operators: "")
        return result
    }
}
