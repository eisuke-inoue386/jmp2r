\name{jmp_metadata}
\alias{jmp_metadata}
\alias{print.jmp_dataset}
\alias{as.data.frame.jmp_dataset}
\title{Inspect a JMP Dataset and Its Metadata}
\description{Inspect preserved metadata or extract the stored data frame.}
\usage{
jmp_metadata(x)
\method{print}{jmp_dataset}(x, ...)
\method{as.data.frame}{jmp_dataset}(x, row.names = NULL, optional = FALSE, ...)
}
\arguments{
\item{x}{A \code{jmp_dataset} returned by a reader.}
\item{row.names}{Optional replacement row names for the extracted data frame.}
\item{optional}{Accepted for compatibility with \code{as.data.frame()}.}
\item{...}{Additional print arguments; ignored by data frame extraction.}
}
\value{\code{jmp_metadata()} returns metadata components as a list.
\code{as.data.frame()} returns stored data without applying JMP analysis
settings. \code{print()} returns its input invisibly.}
\details{Column metadata is indexed by position, even when names are duplicated.
The \code{metadata_known} flags distinguish unavailable information from
known-absent properties. Keep the whole object with \code{saveRDS()} to preserve
metadata and original bytes; a CSV export cannot preserve all these components.}
\examples{
x <- read_jmp(system.file("extdata", "upstream", "example1.jmp",
                         package = "jmp2r"), metadata = "quiet")
nrow(as.data.frame(x))
names(jmp_metadata(x))
}
