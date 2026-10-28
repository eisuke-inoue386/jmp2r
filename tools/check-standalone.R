# Run in a fresh session from the repository root, without installing jmp2r.
source("jmp2r.R", encoding = "UTF-8")
stopifnot(!"package:jmp2r" %in% search())
x <- read_jmp_file("inst/extdata/upstream/example1.jmp", metadata = "quiet",
                   missing_codes = FALSE, factors = FALSE)
stopifnot(identical(as.integer(x$data$ints), 1:4),
          identical(x$data[["char utf8"]][4], "\u8f9b\u53e3"),
          identical(as.data.frame(x), x$data), nrow(x$diagnostics) > 0L)
x <- read_jmp("inst/extdata/upstream/compressed.jmp", metadata = "quiet")
stopifnot(nrow(x$data) == 10000L, all(x$data$numeric == 1), is.factor(x$data$character1))
y <- read_jrp("inst/extdata/embedded-example.jrp", metadata = "quiet")
stopifnot(inherits(y, "jmp_dataset"), nrow(y$data) > 0L,
          identical(as.data.frame(y), y$data), is.na(y$data$score[2]),
          is.factor(y$data$group), is.ordered(y$data$severity))
check_rejection <- function(text, error_class) {
  path <- tempfile(fileext = ".jrp")
  on.exit(unlink(path))
  writeLines(text, path)
  error <- tryCatch(read_jrp(path), error = identity)
  stopifnot(inherits(error, error_class))
}
check_rejection('Open("external.jmp");', "jrp_external_reference_error")
check_rejection('Eval(Parse("New Table()"));', "jrp_dynamic_error")
cat("Standalone JMP/JRP reads and error handling passed.\n")
