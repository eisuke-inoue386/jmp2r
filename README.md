# jmp2r

Read supported JMP `.jmp` tables directly in R without JMP, Python, Julia or
additional R packages. A restricted `.jrp` reader accepts literal embedded
values without executing JSL. R 4.1 or newer is required.

**Experimental 0.4.0.** Supported layouts are tested; this is not a universal
JMP reader or a lossless reproduction of JMP's settings. See
[日本語の説明](README.ja.md), [validation](VALIDATION.md) and
[publication instructions](PUBLISHING.md).

## Use with one source() call

```r
source("https://raw.githubusercontent.com/eisuke-inoue386/jmp2r/main/jmp2r.R", encoding = "UTF-8")
result <- read_jmp_file("my-data.jmp")

head(result)
names(result)
str(result)
View(result)
```

**The result is a standard data frame.** No `$data` extraction is needed.
The reader defaults to removing excluded rows, converting missing codes to
`NA`, nominal columns to factors, and ordinal columns to ordered factors.
Continuous columns retain the supported numeric/date type.

The standalone file contains the reader itself and downloads no additional
code. Save it locally to use `source("jmp2r.R", encoding = "UTF-8")` offline.
Loading code from the URL needs an internet connection; reading data is local
and does not upload files. Source it again after restarting R. For a fixed
version, replace `main` with a reviewed commit SHA or save the file locally.
As with other `source()` calls, only load code you trust; same-named functions
in your environment are replaced.

## Conversion options

```r
# Retain all stored rows and turn off NA/factor conversion:
raw <- read_jmp_file("my-data.jmp", exclude_rows = FALSE,
                     missing_codes = FALSE, factors = FALSE)
```

- Only the **excluded** flag removes a row. Hidden, selected or labelled rows
  alone are retained. The input file is never modified.
- Missing codes become `NA` before factor conversion and are not kept as factor
  levels when conversion is enabled. Supported value labels become factor labels.
- Explicit JMP category order takes precedence. Otherwise ordinal columns use
  `ordinal_order = "sort"`: numeric ascending order and R's locale-dependent
  character order. This fallback is recorded in import diagnostics.
- `ordinal_order = "error"` requires declared order; `"appearance"` uses first
  occurrence in returned rows. Nominal columns without declared order use first
  occurrence. Duplicate labels that would merge different codes are errors.
- Unknown metadata required for an enabled conversion causes an error, even
  with `metadata = "quiet"`. Disable the corresponding conversion explicitly
  to read the stored values instead.

## Import diagnostics

```r
jmp_metadata(result)$diagnostics
```

Plain-data output has only one additional attribute, `jmp_diagnostics`, which
records import/conversion notes. It contains no original file bytes, scripts,
raw column properties or detailed metadata. Warnings about unused units,
formulas and table scripts are omitted. Notes affecting interpreted data, such
as inferred ordinal ordering or unknown datetime timezone, remain visible.
These notes describe the import, not later edits or subsets of the data frame.

`metadata = "quiet"` suppresses warnings while retaining the notes.
`metadata = "error"` stops on remaining notes. Neither option permits
unsupported values, unsafe JRP, or conversions requiring unknown metadata.

## Optional detailed output

```r
details <- read_jmp_file("my-data.jmp", output = "dataset")
details$data
details$columns
details$rows
details$table
details$diagnostics
```

`output = "dataset"` preserves the earlier `jmp_dataset` list interface, with
`data`, `columns`, `rows`, `table`, `scripts`, `diagnostics` and `source`.
`jmp_metadata(details)` returns its metadata. Detailed mode retains fuller
warnings about unsupported settings.

- `rows$row_id` maps returned rows to original one-based positions.
- `table$source_nrows`, `returned_nrows` and `excluded_rows_removed` record filtering.
- Converted columns retain `stored_values`, source definitions, `r_levels`,
  `r_level_labels` and `r_level_order_source` for auditing.
- Detailed mode retains original bytes in `source$bytes` by default, including
  excluded rows. Set `keep_source = FALSE` to omit them. Plain data frames never
  retain these bytes. Byte preservation does not mean the contents were decoded.
- `as_analysis_data(details, ...)` can apply conversions disabled at import.
  Repeated conversion uses preserved codes without reinterpreting labels as
  codes. FALSE options do not undo earlier conversions. A plain data frame can
  already be analyzed directly; later JMP conversions need detailed output.

## Supported formats and limits

The binary reader supports tested numeric/integer and UTF-8 character layouts,
including supported compressed columns. It handles known date/time formats,
value labels, modeling types, literal missing codes/category order, and the
recognized table row-state directory. Empty strings remain empty unless
explicitly defined as missing codes. Int64 values use exact decimal strings.
Datetime timezone is unknown; UTC is only a display convention. Display-format
codes are not rendered as JMP would display them. Row-state columns are
separate from the table's row exclusion flags.

Units, formulas, table scripts, complex properties, display decoration and
other JMP settings are not fully decoded or reproduced. Formula-column stored
values can be read, but formulas are not recalculated. Unknown data layouts fail
rather than silently inventing missing values. Compatibility is fixture-based,
not a guarantee for every JMP version.

The `.jrp` reader accepts UTF-8 text with one literal `New Table(...)`, optionally
preceded by `Names Default To Here(1)` or a simple assignment. Columns must supply
literal stored `Values(...)` or `Set Values(...)`. Simple formula text is inert
and accepted only alongside stored values. External references (`Open`,
`Include`, etc.) fail with `jrp_external_reference_error`. Dynamic expressions,
report commands, multiple tables and unsupported structures fail without execution.
**Ordinary JMP-generated JRP reports often contain unsupported commands even
when they embed data.** See `inst/extdata/embedded-example.jrp` for supported input.

## Package installation

```r
install.packages("remotes")
remotes::install_github("eisuke-inoue386/jmp2r")
library(jmp2r)
result <- read_jmp_file("my-data.jmp")
```

Local source archives can be installed with
`install.packages("jmp2r_0.4.0.tar.gz", repos = NULL, type = "source")`.
The separately built Windows binary is `jmp2r_0.4.0.zip` (`type = "win.binary"`).
`jmp2r-source.zip` is a source-folder archive, not an installable Windows binary.
Package examples using `system.file(..., package = "jmp2r")` require installation.

## Tests and provenance

```sh
R CMD build .
R CMD check --no-manual jmp2r_0.4.0.tar.gz
```

Tests use base R. CI checks the package and standalone file on Windows, macOS
and Linux, including generation consistency. Input size, dimensions,
decompression and JRP nesting/token limits are bounded, but are not a general
sandbox or a fixed peak-memory guarantee.

MIT for jmp2r. Binary parsing derives from these MIT projects:

- [jmp-convert](https://github.com/davidmathers/jmp-convert), David Mathers,
  commit `5024c5aba8be0cbfaa21e5a3be85cd9f8a33c3fc`.
- [JMPReader.jl](https://github.com/jaakkor2/JMPReader.jl), Jaakko Ruohio,
  commit `9fd68aa2651a8dde002ecdbd06af4d8d832b18f2`.

The 19 public fixtures originate from JMPReader.jl. Notices are retained in
`inst/LICENSES/` and `inst/NOTICE`. User-provided files are not in the repository.
JMP is a trademark of JMP Statistical Discovery LLC. This project is not
affiliated with or endorsed by JMP or SAS.
