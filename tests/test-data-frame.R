library(jmp2r)
read_text <- function(text, ...) {
  p <- tempfile(fileext = ".jrp")
  on.exit(unlink(p))
  writeLines(text, p, useBytes = TRUE)
  read_jmp_file(p, ...)
}
text <- paste0('New Table("plain", ',
 'New Column("data", Numeric, Values([1,99,3]), Set Property("Missing Value Codes", {99})),',
 'New Column("source", Character, "Nominal", Values({"b","a","b"})),',
 'New Column("diagnostics", Numeric, "Ordinal", Values([10,2,1])))')
warned <- FALSE
x <- withCallingHandlers(read_text(text), jmp_metadata_warning = function(w) {
  warned <<- TRUE
  invokeRestart("muffleWarning")
})
stopifnot(identical(class(x), "data.frame"),
          identical(names(x), c("data", "source", "diagnostics")),
          nrow(x) == 3L, is.na(x$data[2]), mean(x$data, na.rm = TRUE) == 2,
          is.factor(x$source), is.ordered(x$diagnostics),
          identical(levels(x$diagnostics), c("1","2","10")), !warned,
          identical(jmp_metadata(x)$diagnostics$code, "ordinal_order_inferred"),
          setequal(names(attributes(x)), c("names","class","row.names","jmp_diagnostics")),
          identical(as_analysis_data(x), x))
detailed <- read_text(text, output = "dataset", metadata = "quiet")
stopifnot(inherits(detailed, "jmp_dataset"), is.raw(detailed$source$bytes),
          all(vapply(seq_along(x), function(i) identical(x[[i]], detailed$data[[i]]), TRUE)))
saved <- tempfile(fileext = ".rds")
saveRDS(x, saved)
stopifnot(identical(readRDS(saved), x))
unlink(saved)
e <- tryCatch(as_analysis_data(x, factors = TRUE), error = identity)
stopifnot(inherits(e, "jmp_metadata_error"))

# Unused metadata does not cause warnings or metadata='error' failures for
# plain-data output, while detailed mode still reports its incomplete metadata.
p <- system.file("extdata", "upstream", "singlecolumnsinglerow.jmp", package = "jmp2r")
b <- read_jmp(p, metadata = "error")
stopifnot(is.data.frame(b), nrow(b) == 1L, ncol(b) == 1L,
          nrow(jmp_metadata(b)$diagnostics) == 0L)
e <- tryCatch(read_jmp(p, output = "dataset", metadata = "error"), error = identity)
stopifnot(inherits(e, "jmp_metadata_error"))
e <- tryCatch(read_text(text, metadata = "error"), error = identity)
stopifnot(inherits(e, "jmp_metadata_error")) # order inference remains visible
e <- tryCatch(read_jmp(p, output = "invalid"), error = identity)
stopifnot(inherits(e, "error"))
cat("Plain-data output, diagnostics and detailed compatibility tests passed.\n")
