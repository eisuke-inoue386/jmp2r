library(jmp2r)
read_jmp <- function(...) jmp2r::read_jmp(..., output = "dataset")
read_jrp <- function(...) jmp2r::read_jrp(..., output = "dataset")
read_jmp_file <- function(...) jmp2r::read_jmp_file(..., output = "dataset")
internal <- function(name) getFromNamespace(name, "jmp2r")
expect_error <- function(expr, cls) {
  e <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(e, cls))
}
fixture <- function(name) {
  p <- system.file("extdata", "upstream", name, package = "jmp2r")
  readBin(p, "raw", file.info(p)$size)
}
read_bytes <- function(bytes, ...) {
  p <- tempfile(fileext = ".jmp")
  on.exit(unlink(p))
  writeBin(bytes, p)
  read_jmp_file(p, metadata = "quiet", missing_codes = FALSE, factors = FALSE, ...)
}
state_start <- function(bytes, n) {
  h <- internal(".jmp_header")(bytes, 1e7)
  # Unique property-16 header in these public fixtures; synthetic flag edits
  # exercise the full-file path without redistributing any private input.
  marker <- c(as.raw(c(16, 0)), writeBin(as.integer(n * 8), raw(), size = 4,
                                       endian = "little"), raw(4))
  p <- internal(".jmp_find")(bytes, marker, h$table_header_offset)
  stopifnot(p + 10 + n * 8 <= h$column_index_offset)
  p + 10
}
b <- fixture("example1.jmp")
s <- state_start(b, 4)
b[s + seq(5, by = 8, length.out = 4)] <- as.raw(c(2, 4, 1, 6))
all_rows <- read_bytes(b, exclude_rows = FALSE)
x <- read_bytes(b)
stopifnot(nrow(all_rows$data) == 4L, nrow(x$data) == 2L,
          identical(x$data$ints, all_rows$data$ints[c(2, 3)]),
          identical(x$rows$row_id, 2:3), x$rows$hidden[1], x$rows$selected[2],
          identical(x$table$excluded_rows_removed, c(1L, 4L)),
          x$table$source_nrows == 4L, x$table$returned_nrows == 2L,
          identical(x$source$bytes, b),
          identical(x$columns$time$raw_values, all_rows$columns$time$raw_values[c(2, 3)]))
stopifnot(isTRUE(all.equal(as_analysis_data(all_rows, exclude_rows = TRUE),
                         x$data, check.attributes = FALSE)))
b[s + seq(5, by = 8, length.out = 4)] <- as.raw(rep(2, 4))
empty <- read_bytes(b)
stopifnot(nrow(empty$data) == 0L, ncol(empty$data) == 12L,
          nrow(empty$rows) == 0L, length(empty$columns$time$raw_values) == 0L)

# Unknown row metadata must never silently bypass the default filter.
bad <- fixture("example1.jmp")
h <- internal(".jmp_header")(bad, 1e7)
bad[h$table_header_offset + 1L] <- as.raw(6)
expect_error(read_bytes(bad), "jmp_metadata_error")
stopifnot(nrow(read_bytes(bad, exclude_rows = FALSE)$data) == 4L)
bad <- fixture("example1.jmp")
bad[s - 7L] <- as.raw(31) # property payload no longer equals 8 * nrows
expect_error(read_bytes(bad), "jmp_metadata_error")
stopifnot(is.null(read_bytes(bad, exclude_rows = FALSE)$rows))

# Row-state column payloads and interpreted metadata must align after removal.
b <- fixture("rowstate.jmp")
s <- state_start(b, 3)
b[s + seq(5, by = 8, length.out = 3)] <- as.raw(c(0, 2, 1))
y <- read_bytes(b, exclude_rows = FALSE)
x <- read_bytes(b)
stopifnot(identical(x$rows$row_id, c(1L, 3L)), x$rows$selected[2])
for (i in seq_along(x$columns)) {
  stopifnot(nrow(x$columns[[i]]$row_states) == 2L,
            identical(x$columns[[i]]$raw_row_states,
                      y$columns[[i]]$raw_row_states[c(1:8, 17:24)]))
}

# Complete literal column-property lists only; no evaluation of JSL.
u32 <- function(x) writeBin(as.integer(x), raw(), size = 4, endian = "little")
properties <- function(text) list(list(id = 7, payload = c(
  u32(nchar(text, type = "bytes")), charToRaw(text), u32(-1))))
decode <- internal(".jmp_literal_column_properties")
m <- decode(properties("Missing Value Codes({99, -999})"), FALSE)
stopifnot(m$known, identical(m$missing_value_codes, c(99, -999)))
m <- decode(properties('Missing Value Codes({"Unknown", "NA"})'), TRUE)
stopifnot(m$known, identical(m$missing_value_codes, c("Unknown", "NA")))
m <- decode(properties("Value Order({3, 1, 2})"), FALSE)
stopifnot(m$known, identical(m$value_order, c(3, 1, 2)))
stopifnot(decode(list(list(id = 7, payload = u32(-1))), FALSE)$known)
for (text in c('Missing Value Codes({Open("secret")})',
               'Missing Value Codes({99}); Eval(Parse("anything"));',
               'Missing Value Codes({99}); Missing Value Codes({1});',
               'Missing Value Codes({99 + 1})')) {
  stopifnot(!decode(properties(text), FALSE)$known)
}
broken <- properties("Missing Value Codes({99})")
broken[[1]]$payload <- head(broken[[1]]$payload, -1L)
stopifnot(!decode(broken, FALSE)$known)

# Full binary-column regression: insert a synthetic missing-code declaration
# into the public Float64 fixture, shifting all following column offsets.
u16 <- function(x) writeBin(as.integer(x), raw(), size = 2, endian = "little")
u64 <- function(x) c(u32(x), raw(4))
b <- fixture("example1.jmp")
h <- internal(".jmp_header")(b, 1e7)
cursor <- internal(".jmp_cursor")(b, h$offsets[2])
invisible(cursor$str(2))
cursor$skip(6)
after <- cursor$pos
props <- internal(".jmp_properties")(b, after, h$offsets[3], 5)
start <- after + 5
end <- attr(props, "end_offset")
stopifnot(length(props) == 0L)
# Modeling type is in attribute 23, independent of the storage/type bytes.
scale <- internal(".jmp_find")(b, c(u16(23), u32(2), u16(0)), end)
stopifnot(scale + 8 < h$offsets[3])
b[scale + 7:8] <- u16(1) # Ordinal, without inventing category order
payload <- properties("Missing Value Codes({22.2})")[[1]]$payload
block <- c(u16(1), u64(10 + length(payload)), u16(7), u64(length(payload)), payload)
slice <- internal(".jmp_slice")
b <- c(slice(b, 0, start), block, slice(b, end, length(b) - end))
delta <- length(block) - (end - start)
for (i in 3:h$ncols) {
  offset_pos <- h$column_index_offset + 4 + (i - 1) * 8
  b[offset_pos + 1:8] <- u64(h$offsets[i] + delta)
}
x <- read_bytes(b)
stopifnot(x$columns$floats$modeling_type == "Ordinal",
          x$columns$floats$metadata_known$modeling_type,
          identical(x$columns$floats$missing_value_codes, 22.2),
          is.null(x$columns$floats$value_order))
one <- x
one$data <- x$data[2]
one$columns <- x$columns[2]
d <- as_analysis_data(one, missing_codes = TRUE)
stopifnot(is.na(d[[1]][2]), !is.na(one$data[[1]][2]))
expect_error(as_analysis_data(one, factors = TRUE, ordinal_order = "error"), "jmp_metadata_error")

# Missing codes refer to stored numeric seconds, not converted Date values.
temporal <- read_bytes(fixture("example1.jmp"), exclude_rows = FALSE)
temporal$data <- temporal$data[5]
temporal$columns <- temporal$columns[5]
temporal$columns[[1]]$metadata_known$missing_value_codes <- TRUE
temporal$columns[[1]]$missing_value_codes <- temporal$columns[[1]]$raw_values[2]
temporal$rows$excluded[1] <- TRUE
d <- as_analysis_data(temporal, exclude_rows = TRUE, missing_codes = TRUE)
stopifnot(inherits(d[[1]], "Date"), is.na(d[[1]][1]),
          !is.na(temporal$data[[1]][2]))

cat("Row exclusion and literal metadata tests passed.\n")
