"""Synthetic documents for the markup formats, shared by the sample and fixture generators.

Everything here is authored for this repository. Nothing is copied from a user file and no value
resembles a real credential; the host fixtures add one clearly synthetic secret (@SECRET@ placeholder) on a line the
privacy stage must conceal.
"""

# Theme-page samples: one bounded, secret-free document per format (name, text).
APPEARANCE = {
    'text.latex': ('example.tex', r'''\documentclass{article}
\title{Example document}
\author{Ada Example}
\begin{document}
\maketitle

\section{Introduction}
This paragraph has \emph{emphasis}, \textbf{bold} and \texttt{monospace} text. % a comment
Formulas such as $e^{i\pi} + 1 = 0$ are approximated, not typeset.

\begin{itemize}
  \item A first point
  \item A second point
\end{itemize}

\subsection{An equation}
\begin{equation}
  \frac{a}{b} = \sqrt{x} \leq \alpha + \beta
\end{equation}

\begin{verbatim}
print("hello, preview")
\end{verbatim}
\end{document}
'''),
    'text.bibtex': ('example.bib', '''@article{lovelace1843,
  author  = {Lovelace, Ada and Babbage, Charles},
  title   = {Notes on the Analytical Engine},
  journal = {Scientific Memoirs},
  year    = {1843},
  volume  = {3},
  pages   = {666--731}
}

@book{knuth1984,
  author    = {Knuth, Donald E.},
  title     = {The {TeXbook}},
  publisher = {Addison-Wesley},
  address   = {Reading, MA},
  year      = {1984}
}

@inproceedings{hopper1952,
  author    = {Hopper, Grace Murray},
  title     = {The Education of a Computer},
  booktitle = {Proceedings of the 1952 ACM National Meeting},
  year      = {1952},
  pages     = {243--249}
}
'''),
    'text.asciidoc': ('example.adoc', '''= Example document
Ada Example

== Introduction

A paragraph with *bold*, _italic_ and `monospace` text.

NOTE: Admonitions are shown with a localized title.

* First item
* Second item
** A nested item

. Step one
. Step two

[source,swift]
----
let greeting = "Hello, preview"
----

|===
| Name | Value
| alpha | 1
| beta | 2
|===
'''),
    'text.restructuredtext': ('example.rst', '''Example document
================

Introduction
------------

A paragraph with *emphasis*, **strong text** and ``inline literal`` text.

.. note::

   Admonitions are shown with a localized title.

* First item
* Second item

  * A nested item

1. Step one
2. Step two

::

    literal block
    never executed
'''),
    'text.org': ('example.org', '''#+TITLE: Example document
#+AUTHOR: Ada Example

* Introduction
A paragraph with *bold*, /italic/, =verbatim= and ~code~ text.

** A nested heading
- First item
- Second item
  - A nested item

1. Step one
2. Step two

#+BEGIN_SRC python
print("hello, preview")
#+END_SRC

| Name  | Value |
|-------+-------|
| alpha | 1     |
| beta  | 2     |

* TODO A task heading
'''),
    'text.fountain': ('example.fountain', '''Title: Example Screenplay
Author: Ada Example

FADE IN:

INT. WORKSHOP - DAY

Gears turn on a wooden bench. ADA studies a drawing.

ADA
(quietly)
It should work this time.

BABBAGE
You said that last time.

> THE END <
'''),
}

# Finder-fixture documents (formatID -> (file name, text template)); @SECRET@ marks a value the
# privacy stage must conceal.
HOST_FIXTURES = {
    'text.latex': ('41-latex.tex', r'''\documentclass{article}
\def\apikey{@SECRET@}
% token: @SECRET@
\begin{document}
\section{Preview fixture}
Safe local rendering with $x^2$.
\end{document}
'''),
    'text.bibtex': ('42-references.bib', '''@article{fixture2026,
  author = {Fixture, Preview},
  title = {Safe local rendering},
  year = {2026},
  password = {@SECRET@}
}
'''),
    'text.asciidoc': ('43-document.adoc', '''= Preview fixture
:api-key: @SECRET@

== Safe local rendering

A paragraph.
'''),
    'text.restructuredtext': ('44-document.rst', '''Preview fixture
===============

:password: @SECRET@

.. |token| replace:: @SECRET@

Safe local rendering.
'''),
    'text.org': ('45-notes.org', '''#+TITLE: Preview fixture
#+PROPERTY: password @SECRET@

* Safe local rendering
:PROPERTIES:
:TOKEN: @SECRET@
:END:
'''),
    'text.fountain': ('46-script.fountain', '''Title: Preview fixture
Password: @SECRET@

INT. FIXTURE - DAY

A safe local rendering.
'''),
}
