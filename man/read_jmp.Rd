\name{read_jmp}
\alias{read_jmp}
\alias{read_jrp}
\alias{read_jmp_file}
\title{Read JMP Data Without JMP}
\description{Read supported binary JMP data tables, or a restricted literal
subset of embedded-data JRP scripts. No JSL is executed.}
\usage{
read_jmp(path, metadata = c("warn", "error", "quiet"),
  keep_source = TRUE, max_bytes = 512 * 1024^2, max_cells = 1e7,
  exclude_rows = TRUE, missing_codes = TRUE, factors = TRUE,
  ordinal_order = c("sort", "error", "appearance"),
  output = c("data.frame", "dataset"))

read_jrp(path, metadata = c("warn", "error", "quiet"),
  keep_source = TRUE, max_bytes = 16 * 1024^2, max_cells = 1e7,
  exclude_rows = TRUE, missing_codes = TRUE, factors = TRUE,
  ordinal_order = c("sort", "error", "appearance"),
  output = c("data.frame", "dataset"))

read_jmp_file(path, ...)
}
\arguments{
\item{path}{One local file path. Network URLs are not accepted.}
\item{metadata}{How to handle diagnostic entries: warn and return, stop with
an error, or return quietly. Quiet does not allow undecodable data or unsafe JRP.}
\item{keep_source}{For \code{output = "dataset"}, keep original file bytes
in \code{source$bytes}. Plain data frames never include these bytes.}
\item{max_bytes}{Maximum input file size in bytes, a positive whole number.}
\item{max_cells}{Maximum number of cells, and maximum individual dimension.}
\item{exclude_rows}{Remove JMP-excluded rows from returned data (default TRUE).
Unknown exclusion metadata causes an error even with quiet diagnostics.
Set FALSE explicitly to retain all stored rows. Hidden or selected rows alone
are not removed. Original source bytes, when kept, still contain all rows.}
\item{...}{Arguments passed to \code{read_jmp()} or \code{read_jrp()}.}
\item{missing_codes}{Convert known JMP missing codes to \code{NA} before factor
conversion (default TRUE). Set FALSE to retain the codes as values.}
\item{factors}{Convert nominal columns to factors and ordinal columns to ordered
factors (default TRUE), using supported value labels. Set FALSE to retain values.}
\item{ordinal_order}{When JMP has no explicit category order: \code{"sort"}
uses R's standard order, \code{"appearance"} uses first occurrence in returned
data, and \code{"error"} stops. Inferred orders are recorded in diagnostics.
Character sorting depends on the R session's locale. Explicit JMP order wins.
Inferred order does not emit a warning; explicit strict modes still stop.}
\item{output}{Default \code{"data.frame"} returns the data directly, with
import diagnostics in an attribute accessible through \code{jmp_metadata()}.
\code{"dataset"} returns the detailed list used by earlier versions.}
}
\value{By default a standard \code{data.frame}, with conversions already
applied and a \code{jmp_diagnostics} attribute containing import notes.
With \code{output = "dataset"}, a \code{jmp_dataset} list containing \code{data},
\code{columns} (a list in column order), \code{rows}, \code{table},
\code{scripts}, \code{diagnostics}, and \code{source}.
Unavailable metadata is explicitly marked unknown.}
\details{
The binary reader is experimental and based on independently decoded layouts,
not an official JMP file specification. Unknown metadata is reported; unsupported
data encodings fail instead of silently producing missing columns.

JRP input must be UTF-8 (an optional UTF-8 BOM is accepted). Only a single
literal \code{New Table(...)} with supported literal column definitions is
accepted. External file references, dynamic statements, and unsupported
trailing report code fail. A formula is retained as text only when the stored
values are also supplied. General JMP reports are not supported.

Excluded rows are removed at import by default. In detailed output,
\code{rows$row_id} maps each
returned row to its original one-based position; \code{table$source_nrows},
\code{table$returned_nrows} and \code{table$excluded_rows_removed} record the
filtering. Per-row interpreted column metadata stays aligned with returned data.
The original file is not modified. Missing codes become \code{NA} and nominal/
ordinal columns become factors by default. Required but unknown metadata stops
conversion even in quiet mode; opt out with the corresponding FALSE option.
For converted columns, \code{columns[[i]]$stored_values} retains values before
conversion, aligned with returned rows. Original missing-code definitions,
modeling types and declared order remain in metadata. \code{r_levels},
\code{r_level_labels} and \code{r_level_order_source} describe factor conversion.
The source order is never overwritten by the inferred R order.

Plain-data output omits column/table/script metadata and source bytes. It does
not warn about unsupported units, formulas or table scripts. Notes affecting
data interpretation (such as inferred category order or unknown timezone)
remain visible. Its diagnostic attribute records the import, not subsequent
edits/subsets. Detailed output retains the fuller metadata and diagnostics.

Errors inherit from \code{jmp_error}; metadata warnings inherit from
\code{jmp_metadata_warning}. Input limits bound basic allocations but are not
a general purpose sandbox or a guarantee of a fixed peak memory usage.
}
\examples{
path <- system.file("extdata", "upstream", "compressed.jmp", package = "jmp2r")
x <- read_jmp(path, metadata = "quiet")
names(x)
head(jmp_metadata(x)$diagnostics)
}
\seealso{\code{\link{jmp_metadata}}, \code{\link{as_analysis_data}}}
