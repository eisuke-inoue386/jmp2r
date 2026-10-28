library(jmp2r)

expect_error_class <- function(expr, class) {
  e <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(e, class))
  invisible(e)
}
path <- system.file("extdata", "upstream", "example1.jmp", package = "jmp2r")
warned <- FALSE
x <- withCallingHandlers(read_jmp(path), jmp_metadata_warning = function(w) {
  warned <<- TRUE
  invokeRestart("muffleWarning")
})
stopifnot(warned, inherits(x, "jmp_dataset"), nrow(x$data) == 4L,
          is.raw(x$source$bytes), identical(as.data.frame(x), x$data),
          identical(as_analysis_data(x), x$data))
expect_error_class(read_jmp(path, metadata = "error"), "jmp_metadata_error")
expect_error_class(read_jmp(path, max_bytes = 10), "jmp_resource_error")
expect_error_class(read_jmp(path, max_cells = 0), "jmp_argument_error")
expect_error_class(read_jmp(path, keep_source = NA), "jmp_argument_error")
expect_error_class(read_jmp("https://example.invalid/data.jmp"), "jmp_argument_error")
expect_error_class(read_jmp("a-file-that-does-not-exist.jmp"), "jmp_io_error")
expect_error_class(read_jmp_file("wrong.txt"), "jmp_argument_error")
expect_error_class(read_jmp_file(character()), "jmp_argument_error")
expect_error_class(as_analysis_data(x, exclude_rows = TRUE), "jmp_metadata_error")
expect_error_class(as_analysis_data(x, factors = TRUE), "jmp_metadata_error")
expect_error_class(as_analysis_data(x, missing_codes = TRUE), "jmp_metadata_error")
stopifnot(is.null(read_jmp(path, metadata = "quiet", keep_source = FALSE)$source$bytes))
stopifnot(identical(read_jmp_file(path, metadata = "quiet")$data, x$data))
saved <- tempfile(fileext = ".rds")
saveRDS(x, saved)
stopifnot(identical(readRDS(saved), x))
unlink(saved)

# Transformations require explicit metadata and never mutate the source.
y <- x
y$data <- data.frame(group = c(2, 1, 9, 2))
y$columns <- list(group = list(modeling_type = "Ordinal", value_order = c(1, 2),
  value_labels = list(values = c(1, 2), labels = c("low", "high")),
  missing_value_codes = 9, metadata_known = list(modeling_type = TRUE,
    value_order = TRUE, value_labels = TRUE, missing_value_codes = TRUE)))
y$rows <- data.frame(excluded = c(FALSE, FALSE, FALSE, TRUE))
z <- as_analysis_data(y, exclude_rows = TRUE, missing_codes = TRUE, factors = TRUE)
stopifnot(nrow(z) == 3L, is.ordered(z$group),
          identical(as.character(z$group), c("high", "low", NA_character_)),
          identical(y$data$group, c(2, 1, 9, 2)))
y$columns[[1]]$value_labels$labels <- c("same", "same")
expect_error_class(as_analysis_data(y, missing_codes = TRUE, factors = TRUE), "jmp_metadata_error")
y$rows$excluded[1] <- NA
expect_error_class(as_analysis_data(y, exclude_rows = TRUE), "jmp_metadata_error")

bad_text <- tempfile(fileext = ".jrp")
writeBin(as.raw(c(255, 254, 0, 0)), bad_text)
expect_error_class(read_jrp(bad_text), "jrp_syntax_error")
writeBin(as.raw(c(195, 40)), bad_text)
expect_error_class(read_jrp(bad_text), "jrp_syntax_error")
unlink(bad_text)
cat("Public API tests passed.\n")
