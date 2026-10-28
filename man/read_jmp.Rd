\name{read_jmp}
\alias{read_jmp}
\alias{read_jrp}
\alias{read_jmp_file}
\title{Read JMP Data Without JMP}
\description{Read supported binary JMP data tables, or a restricted literal
subset of embedded-data JRP scripts. No JSL is executed.}
\usage{
read_jmp(path, metadata = c("warn", "error", "quiet"),
  keep_source = TRUE, max_bytes = 512 * 1024^2, max_cells = 1e7)

read_jrp(path, metadata = c("warn", "error", "quiet"),
  keep_source = TRUE, max_bytes = 16 * 1024^2, max_cells = 1e7)

read_jmp_file(path, ...)
}
\arguments{
\item{path}{One local file path. Network URLs are not accepted.}
\item{metadata}{How to handle diagnostic entries: warn and return, stop with
an error, or return quietly. Quiet does not allow undecodable data or unsafe JRP.}
\item{keep_source}{Keep original file bytes in \code{source$bytes}. This
preserves an archival copy, not a promise that all metadata was decoded.}
\item{max_bytes}{Maximum input file size in bytes, a positive whole number.}
\item{max_cells}{Maximum number of cells, and maximum individual dimension.}
\item{...}{Arguments passed to \code{read_jmp()} or \code{read_jrp()}.}
}
\value{A \code{jmp_dataset} list containing \code{data} (a data frame),
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

Ordinary data frame operations do not apply JMP exclusion flags, missing codes,
or modeling types. Use \code{as_analysis_data()} with explicit options, and
keep the original \code{jmp_dataset} for its metadata.

Errors inherit from \code{jmp_error}; metadata warnings inherit from
\code{jmp_metadata_warning}. Input limits bound basic allocations but are not
a general purpose sandbox or a guarantee of a fixed peak memory usage.
}
\examples{
path <- system.file("extdata", "upstream", "example1.jmp", package = "jmp2r")
x <- read_jmp(path, metadata = "quiet")
names(x$data)
head(x$diagnostics)
}
\seealso{\code{\link{jmp_metadata}}, \code{\link{as_analysis_data}}}
