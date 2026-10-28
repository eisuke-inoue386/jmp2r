library(jmp2r)
read_text <- function(text, ...) {
  p <- tempfile(fileext = ".jrp")
  on.exit(unlink(p))
  writeLines(text, p, useBytes = TRUE)
  read_jmp_file(p, metadata = "quiet", ...)
}
expect_error <- function(expr) {
  e <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(e, "jmp_metadata_error"))
}
text <- paste0('New Table("conversion", ',
  'New Column("score", Numeric, "Continuous", Set Property("Missing Value Codes", {99}), Values([1,99,3,.])),',
  'New Column("group", Numeric, "Nominal", Set Property("Missing Value Codes", {99}), ',
  'Set Property("Value Labels", {1="Control",2="Treatment",99="Missing"}), Values([2,1,99,2])),',
  'New Column("rank", Numeric, "Ordinal", Set Property("Missing Value Codes", {99}), Values([10,2,99,1])),',
  'New Column("text rank", Character, "Ordinal", Values({"z","a","m","a"})))')
x <- read_text(text)
stopifnot(identical(x$data$score, c(1,NA_real_,3,NA_real_)),
          is.factor(x$data$group), !is.ordered(x$data$group),
          identical(as.character(x$data$group), c("Treatment","Control",NA,"Treatment")),
          !"Missing" %in% levels(x$data$group),
          is.ordered(x$data$rank), identical(levels(x$data$rank), c("1","2","10")),
          is.na(x$data$rank[3]),
          identical(levels(x$data$`text rank`), sort(c("z","a","m"))),
          sum(x$diagnostics$code == "ordinal_order_inferred") == 2L,
          identical(x$columns$group$stored_values, c(2,1,99,2)),
          identical(x$columns$rank$r_levels, c(1,2,10)),
          x$columns$rank$r_level_order_source == "r_sort",
          is.null(x$columns$rank$value_order))
# Repeated conversion must not remap labels as codes or resurrect missing values.
stopifnot(identical(as_analysis_data(x, missing_codes = TRUE, factors = TRUE), x$data),
          identical(as_analysis_data(x, factors = TRUE), x$data),
          identical(as_analysis_data(x, missing_codes = TRUE), x$data))
raw <- read_text(text, missing_codes = FALSE, factors = FALSE)
stopifnot(identical(raw$data$rank, c(10,2,99,1)), !is.factor(raw$data$group),
          raw$data$score[2] == 99)
only_missing <- read_text(text, factors = FALSE)
stopifnot(is.na(only_missing$data$rank[3]), is.numeric(only_missing$data$rank))
only_factors <- read_text(text, missing_codes = FALSE)
stopifnot("99" %in% levels(only_factors$data$rank), only_factors$data$score[2] == 99)
expect_error(read_text(text, ordinal_order = "error"))
appearance <- read_text(text, ordinal_order = "appearance")
stopifnot(identical(levels(appearance$data$rank), c("10","2","1")))

explicit <- read_text(paste0('New Table("explicit", New Column("rank", Numeric, "Ordinal",',
 'Set Property("Missing Value Codes", {99}), Set Property("Value Order", {3,2,1,99}),',
 'Set Property("Value Labels", {1="Low",2="Mid",3="High",99="Missing"}), Values([1,99,3])))'))
stopifnot(identical(levels(explicit$data$rank), c("High","Mid","Low")),
          is.na(explicit$data$rank[2]),
          !any(explicit$diagnostics$code == "ordinal_order_inferred"),
          explicit$columns$rank$r_level_order_source == "jmp")
empty <- read_text('New Table("empty", New Column("x", Numeric, "Ordinal", Values([])))')
stopifnot(is.ordered(empty$data$x), length(levels(empty$data$x)) == 0L)
all_missing <- read_text(paste0('New Table("all missing", New Column("x", Numeric, "Ordinal",',
  'Set Property("Missing Value Codes", {99}), Values([99,99])))'))
stopifnot(is.ordered(all_missing$data$x), all(is.na(all_missing$data$x)),
          length(levels(all_missing$data$x)) == 0L)
expect_error(read_text(paste0('New Table("collision", New Column("x", Numeric, "Nominal",',
 'Set Property("Value Labels", {1="same",2="same"}), Values([1,2])))')))

# Binary public fixture: defaults apply nominal conversion; numeric storage stays numeric.
p <- system.file("extdata", "upstream", "compressed.jmp", package = "jmp2r")
b <- read_jmp(p, metadata = "quiet")
stopifnot(nrow(b$data) == 10000L, is.numeric(b$data$numeric), is.factor(b$data$character1))
p <- system.file("extdata", "upstream", "example1.jmp", package = "jmp2r")
expect_error(read_jmp(p, metadata = "quiet")) # uninterpreted formula metadata
stopifnot(nrow(read_jmp(p, metadata = "quiet", missing_codes = FALSE, factors = FALSE)$data) == 4L)
for (args in list(list(missing_codes = NA), list(factors = 1))) {
  e <- tryCatch(do.call(read_jmp, c(list(path = p), args)), error = identity)
  stopifnot(inherits(e, "jmp_argument_error"))
}
cat("Default import conversion and repeat-conversion tests passed.\n")
