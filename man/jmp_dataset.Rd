\name{jmp_metadata}
\alias{jmp_metadata}
\alias{print.jmp_dataset}
\alias{as.data.frame.jmp_dataset}
\title{Inspect a JMP Dataset and Its Metadata}
\description{Inspect import diagnostics or detailed metadata.}
\usage{
jmp_metadata(x)
\method{print}{jmp_dataset}(x, ...)
\method{as.data.frame}{jmp_dataset}(x, row.names = NULL, optional = FALSE, ...)
}
\arguments{
\item{x}{For \code{jmp_metadata()}, a data frame or detailed \code{jmp_dataset}
returned by a reader. The S3 methods apply to detailed datasets.}
\item{row.names}{Optional replacement row names for the extracted data frame.}
\item{optional}{Accepted for compatibility with \code{as.data.frame()}.}
\item{...}{Additional print arguments; ignored by data frame extraction.}
}
\value{For plain-data output, \code{jmp_metadata()} returns a list containing
only \code{diagnostics}. For detailed output it returns all metadata components.
\code{as.data.frame()} returns the data already filtered according to the
reader's options (exclusion, missing codes and factors), without further transformations.
\code{print()} returns its input invisibly.}
\details{Use \code{output = "dataset"} at import for detailed metadata.
Column metadata is indexed by position, even when names are duplicated.
The \code{metadata_known} flags distinguish unavailable information from
known-absent properties. Keep the whole object with \code{saveRDS()} to preserve
metadata and original bytes; a CSV export cannot preserve all these components.}
\examples{
x <- read_jmp(system.file("extdata", "upstream", "compressed.jmp",
                         package = "jmp2r"), metadata = "quiet")
nrow(as.data.frame(x))
names(jmp_metadata(x))
}
