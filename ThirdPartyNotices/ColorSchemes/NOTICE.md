# Built-in color scheme palettes

The companion's built-in syntax color schemes reuse published color values only. No source code, theme file,
image or font from these projects is copied, bundled or executed: each scheme is a short table of sRGB hex
values in `Packages/PreviewCore/Sources/PreviewRenderers/NativeColorSchemes.swift`. The values were read from the
upstream files listed below on 2026-10-05, and each upstream project is published under the MIT License.

Where a published value had less than 4.5:1 contrast against its own background, it was moved toward black or
white in the smallest 1% step that reaches 4.5:1. The original value is kept beside each adjusted value in the
source, and [decision 023](../../docs/decisions/023-settings-schema-6-color-schemes-and-provider-diagnostics.md)
lists them. A scheme listed here is therefore adapted from, not identical to, its upstream palette.

| Scheme | Upstream | License | Copyright line (from the upstream license file) |
|---|---|---|---|
| GitHub Light, GitHub Dark | Syntax colors from [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) (`github-markdown-light.css`, `github-markdown-dark.css`), a stylesheet generated from GitHub Primer; Primer's own license is [primer/github-vscode-theme](https://github.com/primer/github-vscode-theme/blob/main/LICENSE) | MIT | Copyright (c) Sindre Sorhus; Copyright (c) 2020 Primer |
| Solarized Light, Solarized Dark | [altercation/solarized](https://github.com/altercation/solarized/blob/master/LICENSE), the 16-color palette | MIT | Copyright (c) 2011 Ethan Schoonover |
| One Light, One Dark | Atom One syntax themes, [`one-light-syntax` and `one-dark-syntax` `styles/colors.less`](https://github.com/atom/atom/tree/master/packages/one-dark-syntax/styles) (HSL definitions converted to sRGB) in [atom/atom](https://github.com/atom/atom/blob/master/LICENSE.md) | MIT | Copyright (c) 2011-2022 GitHub Inc. |
| Nord | [nordtheme/nord](https://github.com/nordtheme/nord/blob/develop/license), `src/nord.less` palette | MIT | Copyright (c) 2016-present Sven Greb |
| Dracula | [dracula/dracula-theme](https://github.com/dracula/dracula-theme/blob/main/LICENSE), palette in the README | MIT | Copyright (c) 2023 Dracula Theme |
| Standard, Paper, Midnight, Aurora | Original to this product | not applicable | not applicable |

The names GitHub, Solarized, One, Nord and Dracula identify the palettes they come from. They do not imply
endorsement by their authors.

## MIT License

Each upstream project above grants the following permission, with its own copyright line from the table.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of
the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
