# jmp2r

Read supported JMP `.jmp` data tables directly in R, without JMP, Python,
Julia, or a compiler. Includes a **non-executing, restricted** reader for
literal embedded tables in `.jrp` files.

**Experimental 0.3.0.** The binary format is undocumented. This is not an
official JMP product, a universal JMP reader, or a lossless semantic converter.
See [日本語の説明](README.ja.md), [validation](VALIDATION.md), and
[publication instructions](PUBLISHING.md).

## Install

R 4.1 or newer is required. The package has no third-party R dependencies.

From the supplied source archive:

```r
install.packages("jmp2r_0.3.0.tar.gz", repos = NULL, type = "source")
```

On Windows, the supplied R binary package can also be installed:

```r
install.packages("jmp2r_0.3.0.zip", repos = NULL, type = "win.binary")
```

From GitHub:

```r
install.packages("remotes")
remotes::install_github("eisuke-inoue386/jmp2r")
```

## Use without installation

Load the standalone file directly from GitHub, in a fresh R session:

```r
source("https://raw.githubusercontent.com/eisuke-inoue386/jmp2r/main/jmp2r.R", encoding = "UTF-8")
x <- read_jmp_file(file.choose())
x$data
x$diagnostics
```

This requires an internet connection to load the code. Data files are read
locally and are not uploaded. Repeat the loading step after restarting R.
For reproducible use, replace `main` in the URL with a reviewed commit SHA.
When using this method, omit `library(jmp2r)`; `system.file(..., package =
"jmp2r")` examples below require package installation instead.

`jmp2r.R` contains the reader itself; it does not fetch additional source files.
You can save this file locally and use `source("jmp2r.R", encoding = "UTF-8")`
offline. It is generated from the package's `R/` files, with licenses included;
CI checks that both distributions stay in sync. As with other `source()` calls,
the code executes in R and defines functions in your working environment.
Only source code you trust. Re-sourcing `main` retrieves the latest version;
use a commit SHA or a saved copy to keep a fixed version.

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
the returned data without further transformations. `jmp_metadata(x)` returns
the other components. Original bytes may include paths or embedded scripts;
they are retained locally and never executed or uploaded. Use
`keep_source = FALSE` to omit them. Keeping bytes is archival preservation,
not evidence that their contents were understood.

## Excluded rows (default: remove)

Since 0.2.0, `read_jmp()`, `read_jrp()` and `read_jmp_file()` default to
`exclude_rows = TRUE`. Only rows flagged **excluded** are removed. Selection,
labeling or hiding alone does not remove a row. To retain all stored rows:

```r
x <- read_jmp_file("my-data.jmp", exclude_rows = FALSE)
```

`x$rows$row_id` contains original one-based row positions. The fields
`x$table$source_nrows`, `x$table$returned_nrows` and
`x$table$excluded_rows_removed` record the import counts and removed positions.
Interpreted per-row metadata stays aligned with the returned data. The original
file is not modified; `x$source$bytes`, if retained, still contains all rows.
Unsupported exclusion metadata stops the default read even with
`metadata = "quiet"`; opt into `exclude_rows = FALSE` to read all rows explicitly.

## Missing codes and factors (default: convert)

Since 0.3.0, `missing_codes = TRUE` converts defined missing codes to `NA`
before `factors = TRUE` converts nominal columns to factors and ordinal columns
to ordered factors. Continuous columns retain their numeric/date type.

```r
x <- read_jmp_file("my-data.jmp")  # analysis-ready data in x$data
raw <- read_jmp_file("my-data.jmp", missing_codes = FALSE, factors = FALSE)
```

Explicit JMP category order takes precedence. Otherwise ordinal levels use R's
standard sorted order (`ordinal_order = "sort"`), which depends on the R locale
for text. This fallback is recorded as `ordinal_order_inferred` in diagnostics.
Use `ordinal_order = "error"` to require explicit order, or `"appearance"` for
first occurrence in the returned rows. Nominal levels without explicit order
use first occurrence. Missing codes are not retained as factor levels when
missing-code conversion is on; duplicate display labels cause an error.

Converted columns retain pre-conversion values in `columns[[i]]$stored_values`,
aligned with returned rows. Source definitions remain unchanged; `r_levels`,
`r_level_labels` and `r_level_order_source` describe the R factor. Unknown
metadata needed for a requested conversion stops the read, even in quiet mode.
Disable that conversion explicitly to retain stored values instead.

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
| Table-wide exclusion/hidden/selection/label flags | Decoded for the supported property directory and eight-byte row-state layout; excluded rows removed by default |
| Modeling type | Supported Continuous/Nominal/Ordinal/RowState attributes retained in column metadata |
| Missing-value definitions and category order | Complete literal `Missing Value Codes` / `Value Order` property lists decoded without execution; complex/unknown lists remain unknown |
| Units, formulas, table scripts, other properties | Not fully decoded; retain available raw property payloads and source bytes |

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

`as_analysis_data()` defaults apply no additional transformations. Reader
defaults already remove exclusions, convert missing codes, and create factors.
This function is useful when conversions were disabled at import. It returns a
new data frame and does not modify `x`. Repeated conversion uses preserved codes
and does not reinterpret labels as original values; FALSE options do not undo
earlier conversions. Unknown required metadata and duplicate labels are errors.

## Tests

```sh
R CMD build .
R CMD check --no-manual jmp2r_0.3.0.tar.gz
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
