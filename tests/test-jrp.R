library(jmp2r)

read_text <- function(text, ...) {
  path <- tempfile(fileext = ".jrp")
  on.exit(unlink(path))
  con <- file(path, "wb")
  writeBin(charToRaw(enc2utf8(text)), con)
  close(con)
  read_jrp(path, metadata = "quiet", missing_codes = FALSE, factors = FALSE, ...)
}
expect_error_class <- function(expr, expected) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, expected))
  invisible(error)
}

example <- read_jrp(system.file("extdata", "embedded-example.jrp", package = "jmp2r"), metadata = "quiet", missing_codes = FALSE, factors = FALSE)
stopifnot(identical(example$data$score, c(10, -99, 30)),
          identical(example$columns$score$missing_value_codes, -99),
          identical(example$columns$group$value_labels$values, c(1, 2)),
          identical(example$columns$group$value_labels$labels, c("Control", "Treatment")),
          identical(example$columns$severity$value_order, c("low", "medium", "high")),
          identical(example$columns$`double score`$formula, ":score * 2"),
          identical(example$rows$excluded, rep(FALSE, 3)))
analysis <- as_analysis_data(example, exclude_rows = TRUE, missing_codes = TRUE, factors = TRUE)
stopifnot(is.na(analysis$score[[2L]]), is.factor(analysis$group),
          identical(levels(analysis$group), c("Control", "Treatment")),
          is.ordered(analysis$severity),
          identical(levels(analysis$severity), c("low", "medium", "high")),
          identical(example$data$score[[2L]], -99))

basic <- 'New Table("test", Add Rows(2), New Column("x", Numeric, Values([1, .])));'
stopifnot(identical(read_text(basic)$data$x, c(1, NA_real_)))
stopifnot(identical(read_text('NewTable("t", NewColumn("x",Numeric,Values([-1.5, +2e2])))')$data$x, c(-1.5, 200)))
stopifnot(identical(read_text('New Table("t", New Column("x", Character, Set Values({"a", "b"})))')$columns$x$modeling_type, "Nominal"))
stopifnot(nrow(read_text('New Table("empty", Add Rows(0), New Column("x", Numeric, Values([])))')$data) == 0L)
stopifnot(nrow(read_text('New Table("empty", Add Rows(2))')$data) == 2L)

# Comments and string literals are not misidentified as external references.
strings <- '/* Open("ignored.jmp"); */ New Table("t", New Column("x", Character, Values({"Open(never)", "quoted \\!\"value\\!\"", "line\\!nnext"}))); // Include("ignored")'
string_values <- read_text(strings)$data$x
stopifnot(identical(string_values, c("Open(never)", 'quoted "value"', "line\nnext")))
japanese <- paste0('New Table("', "\u30c7\u30fc\u30bf", '", New Column("', "\u7fa4", '", Character, Values({"', "\u5bfe\u7167", '"})))')
stopifnot(identical(read_text(japanese)$data[[1L]], "\u5bfe\u7167"))

for (text in c('Open("data.jmp");', 'oPeN("data.jmp")',
               paste0(basic, ' Include("other.jsl");'),
               'New Table("t", New Column("x", Numeric, Values(Open("data.jmp"))))',
               'New Table("t", New Column("x", Numeric, Formula(Open("data.jmp")), Values([1])))',
               'New Table("t", Set Property("a", Load Text File("secret")))')) {
  expect_error_class(read_text(text), "jrp_external_reference_error")
}
for (text in c('Eval(Parse("New Table()"));', 'dt = source;',
               paste0(basic, ' Run Program("anything");'),
               paste0(basic, ' Distribution(Column("x"));'),
               'New Table("t", New Column("x", Numeric, Formula(:a * 2)))',
               'New Table("t", New Column("x", Numeric, Values([1 + 2])))',
               'New Table("t", New Column("x", Numeric, Values([variable])))',
               'New Table("t", New Column("x", Numeric, Values(Random Normal())))',
               'New Table("t", New Column("x", Numeric, Values([1]), Formula(Eval(:x))))',
               'New Table("t", New Column("x", Numeric, Values([1]), Formula(Custom Function(:x))))',
               'New Table("t", New Column("x", Numeric, Values([1]), Formula(a=1; :x)))',
               'New Table("t", Set Row States([1]))',
               'New Table("t", Set Property("p", Function({x}, x)))')) {
  error <- tryCatch(read_text(text), error = identity)
  stopifnot(inherits(error, "jrp_dynamic_error") || inherits(error, "jrp_syntax_error"))
}
for (text in c('New Table("t", Add Rows(1e999))', 'New Table("t", Add Rows(-1))',
               'New Table("t", Add Rows(1.5))',
               'New Table("t", New Column("x", Numeric, Values([1]), Values([2])))',
               'New Table("t", New Column("x", Numeric, Values([1])), New Column("x", Numeric, Values([2])))',
               'New Table("t", New Column("x", Numeric, Values([1])), New Column("y", Numeric, Values([1, 2])))',
               'New Table("t", Add Rows(2), New Column("x", Numeric, Values([1])))',
               'New Table("t", New Column("x", Numeric, Values({"text"})))',
               'New Table("t", New Column("x", Numeric, Values([1]), Value Labels({1="a",1="b"})))',
               'New Table("unterminated)', '/* unclosed',
               'New Table("t", New Column("x", Numeric, Values([1,])))')) {
  expect_error_class(read_text(text), "jrp_syntax_error")
}
expect_error_class(read_text(paste0(basic, basic)), "jmp_unsupported_error")
expect_error_class(read_text('New Table("t", Add Rows(1000000000))', max_cells = 100), "jmp_resource_error")
expect_error_class(read_text(basic, max_cells = 1), "jmp_resource_error")
deep <- paste0('New Table("t", Set Property("p", ', paste(rep("{", 70), collapse = ""),
               '1', paste(rep("}", 70), collapse = ""), '))')
expect_error_class(read_text(deep), "jmp_resource_error")

# Original bytes, properties, and inert scripts survive R serialization.
cache <- tempfile(fileext = ".rds")
saveRDS(example, cache)
restored <- readRDS(cache)
unlink(cache)
stopifnot(identical(restored, example))
