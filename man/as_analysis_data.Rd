\name{as_analysis_data}
\alias{as_analysis_data}
\title{Apply Explicit JMP Analysis Settings}
\description{Derive a data frame from a JMP dataset while keeping the source
object unchanged. Each requested transformation requires known metadata.}
\usage{
as_analysis_data(x, exclude_rows = FALSE, missing_codes = FALSE,
  factors = FALSE)
}
\arguments{
\item{x}{A \code{jmp_dataset}.}
\item{exclude_rows}{Remove rows whose known exclusion flag is true.}
\item{missing_codes}{Convert explicitly declared missing value codes to NA.}
\item{factors}{Convert nominal columns to factors and ordinal columns to ordered
factors. A known explicit Value Order is required for ordinal columns.}
}
\value{A data frame.}
\details{
Defaults return the stored data. When requested metadata is unavailable, this
function stops rather than guessing. In particular, the current binary reader
does not decode table-wide row exclusions or modeling types, so these options
normally require a supported embedded JRP table or deliberately supplied metadata.

Nominal levels without an explicit order follow first occurrence. Stored value
labels are used as factor labels, but duplicate labels that would merge different
codes cause an error. Value Order must include every observed non-missing value.
Ordinary R modeling functions do not honor JMP metadata on their own.
}
\examples{
x <- read_jmp(system.file("extdata", "upstream", "example1.jmp",
                         package = "jmp2r"), metadata = "quiet")
d <- as_analysis_data(x)
ncol(d)
}
