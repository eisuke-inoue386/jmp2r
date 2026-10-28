# jmp2r

Read supported JMP `.jmp` data tables directly in R, without JMP, Python,
Julia, or a compiler. Includes a **non-executing, restricted** reader for
literal embedded tables in `.jrp` files.

**Experimental 0.1.0.** The binary format is undocumented. This is not an
official JMP product, a universal JMP reader, or a lossless semantic converter.
See [日本語の説明](README.ja.md), [validation](VALIDATION.md), and
[publication instructions](PUBLISHING.md).

## Install

R 4.1 or newer is required. The package has no third-party R dependencies.

From the supplied source archive:

```r
install.packages("jmp2r_0.1.0.tar.gz", repos = NULL, type = "source")
```

On Windows, the supplied R binary package can also be installed:

```r
install.packages("jmp2r_0.1.0.zip", repos = NULL, type = "win.binary")
```

From GitHub:

```r
install.packages("remotes")
remotes::install_github("eisuke-inoue386/jmp2r")
```

## Use without installation

Load the three R source files directly from GitHub, in a fresh R session:

```r
base_url <- "https://raw.githubusercontent.com/eisuke-inoue386/jmp2r/main/R/"
for (f in c("binary.R", "jrp.R", "read.R")) {
  source(paste0(base_url, f), encoding = "UTF-8")
}
x <- read_jmp_file(file.choose())
x$data
x$diagnostics
```

This requires an internet connection to load the code. Data files are read
locally and are not uploaded. Repeat the loading step after restarting R.
For reproducible use, replace `main` in the URL with a reviewed commit SHA.
When using this method, omit `library(jmp2r)`; `system.file(..., package =
"jmp2r")` examples below require package installation instead.

## Read a table

```r
library(jmp2r)
x <- read_jmp("my-data.jmp")
d <- x$data
x$columns[[1]]
x$diagnostics
saveRDS(x, "import-with-metadata.rds")
```

The return value is a `jmp_dataset` list:

| Component | Contents |
|---|---|
| `data` | Data frame, original column names and order |
| `columns` | Metadata in column order; `metadata_known` flags distinguish unknown from absent |
| `rows` | Known table-wide row states, or `NULL` when unavailable |
| `table` | Table/header information |
| `scripts` | Inert script text where supported |
| `diagnostics` | Unavailable metadata and representation decisions |
| `source` | Reader version, file basename, size, and original bytes by default |

`read_jmp_file()` dispatches on `.jmp`/`.jrp`. `as.data.frame(x)` extracts
the data without applying JMP analysis settings. `jmp_metadata(x)` returns
the other components. Original bytes may include paths or embedded scripts;
they are retained locally and never executed or uploaded. Use
`keep_source = FALSE` to omit them. Keeping bytes is archival preservation,
not evidence that their contents were understood.

## Binary `.jmp` support

| Information | Current behavior |
|---|---|
| Numeric and byte integer columns | Read stored values; numerical missing values become `NA` |
| Character columns | UTF-8; fixed, variable, compact, coded and supported gzip layouts |
| Empty strings | Retained as `""`, not silently replaced by `NA` |
| Dates/datetimes/durations | Converted where known; original numeric values retained in column metadata |
| Datetime timezone | Unknown; `UTC` is a display convention, explicitly diagnosed |
| 64-bit integer values | Exact decimal strings; never rounded to doubles |
| Value labels | Decoded where the known property layout is recognized; original codes retained |
| Display formats | Raw format codes and known widths retained, not rendered as JMP displays them |
| Row-state **columns** | Marker/color decoded, raw state bytes retained |
| Table-wide exclusion/hidden/selection flags | **Not decoded**, `rows = NULL` |
| Modeling type, units, missing-value definitions, category order, formulas, table scripts | **Not decoded semantically**; retain available raw property payloads and source bytes |

Unknown data layouts fail. Unknown metadata is diagnosed. Do not infer that
missing metadata means a property was absent in JMP. `metadata = "quiet"`
suppresses the warning but retains diagnostics; `metadata = "error"` stops
on any diagnostic entry. The default is `metadata = "warn"`.

The implementation has been compared against the expected contents of 19
MIT-licensed upstream fixtures. This is a fixture-based compatibility claim,
not a guarantee for every file saved by a particular JMP version.

## Restricted `.jrp` support

```r
p <- system.file("extdata", "embedded-example.jrp", package = "jmp2r")
x <- read_jrp(p)
x$data
x$columns
```

Only UTF-8 text containing one literal `New Table(...)` is accepted. Optional
`Names Default To Here(1)` and a simple table assignment are supported.
Each numeric/character column must supply its stored `Values(...)` or
`Set Values(...)`. Literal modeling types, labels, missing codes, value order,
column/table properties, and selected column attributes are preserved.
Simple formula text may be retained **only with explicit stored values**.
It is never calculated.

The following fail without executing any part of the file:

- External references such as `Open(...)` or `Include(...)`:
  `jrp_external_reference_error`.
- Expressions that need execution, unsupported report commands, variable-based
  values, loops, function definitions and trailing executable statements:
  `jrp_dynamic_error` (or a syntax/unsupported error for other invalid input).
- Multiple tables, unsupported encodings or unsupported literal structures:
  a clear syntax/unsupported error.

**Ordinary JMP-generated `.jrp` reports often contain report commands and will
be rejected in this first version**, even when they embed data. This package
does not run an analysis, render a report, or provide a general JSL interpreter.
See the included example for the exact supported style.

## Explicit analysis conversion

```r
# Only when all necessary metadata is known:
d <- as_analysis_data(x, exclude_rows = TRUE,
                      missing_codes = TRUE, factors = TRUE)
```

Defaults apply no transformations. Requested transformations fail when metadata
is unavailable. Binary `.jmp` modeling types, exclusion flags, and missing-value
definitions currently are unavailable, so the corresponding options stop.
For supported literal JRP tables, nominal/ordinal information is available.
Ordinal conversion requires explicit `Value Order`; duplicate display labels
that would merge distinct codes cause an error. The original object is unchanged.

## Tests

```sh
R CMD build .
R CMD check --no-manual jmp2r_0.1.0.tar.gz
```

Tests use base R. The GitHub workflow runs on Windows, macOS and Linux after
the repository is published. Input size, table dimensions, decompression and
JRP nesting/token budgets are bounded. These are defensive limits, not a fixed
peak-memory guarantee or an operating-system sandbox.

## Provenance and license

MIT for jmp2r. Binary reading is derived from:

- [jmp-convert](https://github.com/davidmathers/jmp-convert), David Mathers,
  commit `5024c5aba8be0cbfaa21e5a3be85cd9f8a33c3fc` (MIT).
- [JMPReader.jl](https://github.com/jaakkor2/JMPReader.jl), Jaakko Ruohio,
  commit `9fd68aa2651a8dde002ecdbd06af4d8d832b18f2` (MIT).

The fixture data originate from JMPReader.jl. Original copyright and permission
notices are included in `inst/LICENSES/`. See `inst/NOTICE`.

JMP is a trademark of JMP Statistical Discovery LLC. This project is not
affiliated with or endorsed by JMP or SAS.
