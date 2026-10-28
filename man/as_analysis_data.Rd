\name{as_analysis_data}
\alias{as_analysis_data}
\title{Apply Explicit JMP Analysis Settings}
\description{Derive a data frame from a JMP dataset while keeping the source
object unchanged. Each requested transformation requires known metadata.}
\usage{
as_analysis_data(x, exclude_rows = FALSE, missing_codes = FALSE,
  factors = FALSE, ordinal_order = c("sort", "error", "appearance"))
}
\arguments{
\item{x}{A \code{jmp_dataset}.}
\item{exclude_rows}{Remove rows whose known exclusion flag is true.}
\item{missing_codes}{Convert explicitly declared missing value codes to NA.}
\item{factors}{Convert nominal columns to factors and ordinal columns to ordered
factors. Explicit JMP Value Order takes precedence.}
\item{ordinal_order}{Fallback for ordinal columns without a declared order:
\code{"sort"} (R standard order), \code{"error"}, or \code{"appearance"}.
Character sorting depends on the R locale.}
}
\value{A data frame.}
\details{
Defaults return the imported data, including conversions already applied by
the reader. They do not undo conversions. When requested metadata is unavailable, this
function stops rather than guessing. Readers remove excluded rows by default;
use \code{exclude_rows = FALSE} at import to retain them for later filtering.
Supported binary layouts provide row flags, modeling types and literal missing
codes. More complex properties can remain unknown, as indicated in the metadata.

Nominal levels without an explicit order follow first occurrence. Ordinal levels
without an explicit order use \code{ordinal_order}. For an audit of inferred
orders, use the reader's conversion options, which retain diagnostics and the
effective R levels in the returned metadata. Repeated conversion of imported
data uses preserved codes and does not reinterpret labels as original codes.
Stored value
labels are used as factor labels, but duplicate labels that would merge different
codes cause an error. Value Order must include every observed non-missing value.
Ordinary R modeling functions do not honor JMP metadata on their own.
}
\examples{
x <- read_jmp(system.file("extdata", "upstream", "compressed.jmp",
                         package = "jmp2r"), metadata = "quiet")
d <- as_analysis_data(x)
ncol(d)
}
