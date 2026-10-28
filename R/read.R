# Public API. Parsing never evaluates JSL, R expressions, or shell commands.

.jmp_abort <- function(message, subclass = "jmp_error", ...) {
  stop(structure(c(list(message = message, call = NULL), list(...)),
                 class = unique(c(subclass, "jmp_error", "error", "condition"))))
}

.jmp_flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x))
    .jmp_abort(paste0("'", name, "' must be TRUE or FALSE."), "jmp_argument_error")
  x
}

.jmp_limit <- function(x, name) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x < 1 || x > .Machine$integer.max || x != floor(x))
    .jmp_abort(paste0("'", name, "' must be a positive whole number <= ",
                      .Machine$integer.max, "."), "jmp_argument_error")
  as.double(x)
}

.jmp_read_bytes <- function(path, max_bytes) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path))
    .jmp_abort("'path' must be one nonempty local file path.", "jmp_argument_error")
  if (grepl("^[[:alpha:]][[:alnum:]+.-]*://", path))
    .jmp_abort("Only local files are accepted; URLs are not fetched.", "jmp_argument_error")
  info <- file.info(path)
  if (is.na(info$size) || isTRUE(info$isdir))
    .jmp_abort(paste0("File does not exist or is not a regular file: ", path), "jmp_io_error")
  if (info$size > max_bytes)
    .jmp_abort("File exceeds 'max_bytes'.", "jmp_resource_error")
  con <- tryCatch(file(path, "rb"), error = function(e)
    .jmp_abort(conditionMessage(e), "jmp_io_error"))
  on.exit(close(con), add = TRUE)
  bytes <- readBin(con, "raw", n = as.integer(min(max_bytes + 1, .Machine$integer.max)))
  if (length(bytes) > max_bytes)
    .jmp_abort("File exceeds 'max_bytes'.", "jmp_resource_error")
  bytes
}

.jmp_filter_rows <- function(result, exclude_rows) {
  n <- nrow(result$data)
  result$table$source_nrows <- n
  result$table$excluded_rows_removed <- integer()
  result$table$exclude_rows <- exclude_rows
  if (exclude_rows) {
    flags <- result$rows$excluded
    if (is.null(flags) || !is.logical(flags) || length(flags) != n || anyNA(flags))
      .jmp_abort(paste0("Row exclusion metadata is unavailable; cannot safely remove excluded rows. ",
                       "Use exclude_rows = FALSE to explicitly read all rows."), "jmp_metadata_error")
    keep <- !flags
    result$table$excluded_rows_removed <- result$rows$row_id[flags]
    if (any(flags)) {
      result$data <- result$data[keep, , drop = FALSE]
      rownames(result$data) <- NULL
      result$rows <- result$rows[keep, , drop = FALSE]
      rownames(result$rows) <- NULL
      for (i in seq_along(result$columns)) {
        m <- result$columns[[i]]
        if (!is.null(m$raw_values)) m$raw_values <- m$raw_values[keep]
        if (!is.null(m$row_states)) {
          m$row_states <- m$row_states[keep, , drop = FALSE]
          rownames(m$row_states) <- NULL
        }
        if (!is.null(m$raw_row_states)) {
          width <- as.integer(m$type_bytes[5])
          if (length(m$raw_row_states) != n * width)
            .jmp_abort("Row-state column metadata cannot be aligned after filtering.", "jmp_corrupt_error")
          m$raw_row_states <- as.raw(matrix(m$raw_row_states, nrow = width)[, keep, drop = FALSE])
        }
        result$columns[[i]] <- m
      }
    }
  }
  result$table$returned_nrows <- nrow(result$data)
  result
}

.jmp_finish <- function(result, path, bytes, keep_source, metadata, exclude_rows,
                        missing_codes, factors, ordinal_order, output) {
  if (!is.data.frame(result$data) || length(result$columns) != ncol(result$data))
    .jmp_abort("Reader returned inconsistent column metadata.", "jmp_corrupt_error")
  if (!is.null(result$rows) && nrow(result$rows) != nrow(result$data))
    .jmp_abort("Reader returned inconsistent row metadata.", "jmp_corrupt_error")
  if (is.null(result$diagnostics))
    result$diagnostics <- data.frame(code = character(), scope = character(),
                                     message = character(), stringsAsFactors = FALSE)
  if (is.null(result$scripts)) result$scripts <- list()
  if (is.null(result$table)) result$table <- list()
  result <- .jmp_filter_rows(result, exclude_rows)
  result$source <- list(file = basename(path), size = length(bytes),
                        reader = "jmp2r", version = "0.4.1", backend = "base-R")
  if (keep_source) result$source$bytes <- bytes
  class(result) <- "jmp_dataset"
  converted <- .jmp_analysis_result(result, FALSE, missing_codes, factors, ordinal_order)
  result$data <- converted$data
  result$columns <- converted$columns
  result$diagnostics <- converted$diagnostics
  result$table$missing_codes <- missing_codes
  result$table$factors <- factors
  result$table$ordinal_order <- ordinal_order
  if (output == "data.frame") {
    # Plain-data output omits archival/script metadata. Keep only import notes
    # relevant to values and conversions, not warnings about unused features.
    skip <- result$diagnostics$code %in% c("binary_metadata_partial", "jrp_literal_subset") |
      startsWith(result$diagnostics$message, "Ordinal modeling type is retained, but category order is not explicit;")
    result$diagnostics <- result$diagnostics[!skip, , drop = FALSE]
    rownames(result$diagnostics) <- NULL
  }
  reported <- result$diagnostics
  if (metadata == "warn")
    reported <- reported[reported$code != "ordinal_order_inferred", , drop = FALSE]
  if (nrow(reported)) {
    msg <- paste0("JMP import has ", nrow(reported),
                  " diagnostic entries. See jmp_metadata(result)$diagnostics.")
    if (metadata == "error")
      .jmp_abort(msg, "jmp_metadata_error", diagnostics = result$diagnostics)
    if (metadata == "warn")
      warning(structure(list(message = msg, call = NULL, diagnostics = reported),
                        class = c("jmp_metadata_warning", "warning", "condition")))
  }
  if (output == "data.frame") {
    out <- result$data
    attr(out, "jmp_diagnostics") <- result$diagnostics
    return(out)
  }
  result
}

read_jmp <- function(path, metadata = c("warn", "error", "quiet"),
                     keep_source = TRUE, max_bytes = 512 * 1024^2, max_cells = 1e7,
                     exclude_rows = TRUE, missing_codes = TRUE, factors = TRUE,
                     ordinal_order = c("sort", "error", "appearance"),
                     output = c("data.frame", "dataset")) {
  metadata <- match.arg(metadata)
  output <- match.arg(output)
  ordinal_order <- match.arg(ordinal_order)
  missing_codes <- .jmp_flag(missing_codes, "missing_codes")
  factors <- .jmp_flag(factors, "factors")
  exclude_rows <- .jmp_flag(exclude_rows, "exclude_rows")
  keep_source <- .jmp_flag(keep_source, "keep_source")
  max_bytes <- .jmp_limit(max_bytes, "max_bytes")
  max_cells <- .jmp_limit(max_cells, "max_cells")
  bytes <- .jmp_read_bytes(path, max_bytes)
  result <- .read_jmp_binary(bytes, max_cells = max_cells)
  .jmp_finish(result, path, bytes, keep_source, metadata, exclude_rows,
              missing_codes, factors, ordinal_order, output)
}

read_jrp <- function(path, metadata = c("warn", "error", "quiet"),
                     keep_source = TRUE, max_bytes = 16 * 1024^2, max_cells = 1e7,
                     exclude_rows = TRUE, missing_codes = TRUE, factors = TRUE,
                     ordinal_order = c("sort", "error", "appearance"),
                     output = c("data.frame", "dataset")) {
  metadata <- match.arg(metadata)
  output <- match.arg(output)
  ordinal_order <- match.arg(ordinal_order)
  missing_codes <- .jmp_flag(missing_codes, "missing_codes")
  factors <- .jmp_flag(factors, "factors")
  exclude_rows <- .jmp_flag(exclude_rows, "exclude_rows")
  keep_source <- .jmp_flag(keep_source, "keep_source")
  max_bytes <- .jmp_limit(max_bytes, "max_bytes")
  max_cells <- .jmp_limit(max_cells, "max_cells")
  bytes <- .jmp_read_bytes(path, max_bytes)
  text_bytes <- bytes
  if (length(text_bytes) >= 3L && identical(text_bytes[1:3], as.raw(c(239, 187, 191))))
    text_bytes <- text_bytes[-(1:3)]
  if (any(text_bytes == as.raw(0)))
    .jmp_abort("JRP must be UTF-8 text without NUL bytes; UTF-16 is not supported.",
               "jrp_syntax_error")
  text <- rawToChar(text_bytes)
  if (is.na(iconv(text, from = "UTF-8", to = "UTF-8", sub = NA_character_)))
    .jmp_abort("JRP text is not valid UTF-8.", "jrp_syntax_error")
  Encoding(text) <- "UTF-8"
  result <- .read_jrp_text(text, max_cells = max_cells)
  .jmp_finish(result, path, bytes, keep_source, metadata, exclude_rows,
              missing_codes, factors, ordinal_order, output)
}

read_jmp_file <- function(path, ...) {
  if (!is.character(path) || length(path) != 1L || is.na(path))
    .jmp_abort("'path' must be one local file path.", "jmp_argument_error")
  extension <- tolower(sub("^.*\\.", "", basename(path)))
  switch(extension, jmp = read_jmp(path, ...), jrp = read_jrp(path, ...),
         .jmp_abort("Expected a .jmp or .jrp file extension.", "jmp_argument_error"))
}

jmp_metadata <- function(x) {
  if (is.data.frame(x) && !is.null(attr(x, "jmp_diagnostics", exact = TRUE)))
    return(list(diagnostics = attr(x, "jmp_diagnostics", exact = TRUE)))
  if (!inherits(x, "jmp_dataset"))
    .jmp_abort("'x' must be a jmp2r data frame or jmp_dataset.", "jmp_argument_error")
  x[c("columns", "rows", "table", "scripts", "diagnostics", "source")]
}

print.jmp_dataset <- function(x, ...) {
  cat("<jmp_dataset> ", nrow(x$data), " rows x ", ncol(x$data), " columns\n", sep = "")
  cat("Source: ", x$source$file, " (", x$source$backend, ")\n", sep = "")
  cat("Metadata diagnostics: ", nrow(x$diagnostics), "\n", sep = "")
  print(utils::head(x$data), ...)
  invisible(x)
}

as.data.frame.jmp_dataset <- function(x, row.names = NULL, optional = FALSE, ...) {
  out <- x$data
  if (!is.null(row.names)) row.names(out) <- row.names
  out
}

.jmp_known <- function(meta, field) {
  isTRUE(meta$metadata_known[[field]])
}

as_analysis_data <- function(x, exclude_rows = FALSE, missing_codes = FALSE,
                             factors = FALSE,
                             ordinal_order = c("sort", "error", "appearance")) {
  if (is.data.frame(x)) {
    exclude_rows <- .jmp_flag(exclude_rows, "exclude_rows")
    missing_codes <- .jmp_flag(missing_codes, "missing_codes")
    factors <- .jmp_flag(factors, "factors")
    if (exclude_rows || missing_codes || factors)
      .jmp_abort(paste0("A data frame is already the imported data; further JMP conversions require ",
                       "reading with output = 'dataset' or setting conversion options at import."),
                 "jmp_metadata_error")
    return(x)
  }
  .jmp_analysis_result(x, exclude_rows, missing_codes, factors,
                       match.arg(ordinal_order))$data
}

.jmp_analysis_result <- function(x, exclude_rows, missing_codes, factors, ordinal_order) {
  if (!inherits(x, "jmp_dataset"))
    .jmp_abort("'x' must be a jmp_dataset.", "jmp_argument_error")
  exclude_rows <- .jmp_flag(exclude_rows, "exclude_rows")
  missing_codes <- .jmp_flag(missing_codes, "missing_codes")
  factors <- .jmp_flag(factors, "factors")
  d <- x$data
  columns <- x$columns
  diagnostics <- x$diagnostics
  kept <- rep(TRUE, nrow(d))
  if (exclude_rows) {
    if (is.null(x$rows) || is.null(x$rows$excluded) || anyNA(x$rows$excluded))
      .jmp_abort("Row exclusion metadata is unavailable; cannot apply exclude_rows=TRUE.",
                 "jmp_metadata_error")
    if (!is.logical(x$rows$excluded) || length(x$rows$excluded) != nrow(d))
      .jmp_abort("Invalid row exclusion metadata.", "jmp_metadata_error")
    kept <- !x$rows$excluded
    d <- d[kept, , drop = FALSE]
  }
  for (i in seq_along(d)) {
    m <- x$columns[[i]]
    stored <- if (!is.null(m$stored_values)) m$stored_values[kept] else d[[i]]
    if (missing_codes) {
      if (!.jmp_known(m, "missing_value_codes"))
        .jmp_abort(paste0("Missing-value definitions are unavailable for column '",
                           names(d)[i], "'."), "jmp_metadata_error")
      codes <- m$missing_value_codes
      if (length(codes)) {
        code_values <- stored
        if (!is.null(m$raw_values)) {
          if (length(m$raw_values) != nrow(x$data))
            .jmp_abort("Stored values do not align with the data rows.", "jmp_metadata_error")
          code_values <- m$raw_values[kept]
        }
        d[[i]][code_values %in% codes] <- NA
        m$stored_values <- stored
      }
      m$missing_codes_applied <- TRUE
    }
    if (factors) {
      if (!.jmp_known(m, "modeling_type") || length(m$modeling_type) != 1L ||
          is.na(m$modeling_type))
        .jmp_abort(paste0("Modeling type is unavailable for column '", names(d)[i], "'."),
                   "jmp_metadata_error")
      kind <- tolower(m$modeling_type)
      if (!kind %in% c("continuous", "nominal", "ordinal", "rowstate", "none"))
        .jmp_abort(paste0("Unsupported modeling type: ", m$modeling_type),
                   "jmp_metadata_error")
      if (kind %in% c("nominal", "ordinal")) {
        if (!.jmp_known(m, "value_order") || !.jmp_known(m, "value_labels"))
          .jmp_abort(paste0("Category metadata is unavailable for column '",
                             names(d)[i], "'."), "jmp_metadata_error")
        values <- stored
        # Keep previously converted missing values missing when conversion is
        # requested again; labels are never treated as the original codes.
        values[is.na(d[[i]])] <- NA
        lev <- m$value_order
        order_source <- "jmp"
        if (!length(lev)) {
          if (kind == "ordinal" && ordinal_order == "error")
            .jmp_abort(paste0("Ordinal column '", names(d)[i],
                               "' has no explicit Value Order."), "jmp_metadata_error")
          lev <- unique(values[!is.na(values)])
          if (kind == "ordinal" && ordinal_order == "sort") {
            lev <- sort(lev)
            order_source <- "r_sort"
          } else order_source <- "first_appearance"
          if (kind == "ordinal") diagnostics <- rbind(diagnostics, data.frame(
            code = "ordinal_order_inferred", scope = names(d)[i],
            message = if (ordinal_order == "sort")
              "No explicit JMP category order; ordered factor uses R's standard sorted order (character order depends on the R locale)."
            else "No explicit JMP category order; ordered factor uses first appearance in the returned data.",
            stringsAsFactors = FALSE))
        }
        if (isTRUE(m$missing_codes_applied) && length(m$missing_value_codes))
          lev <- lev[!lev %in% m$missing_value_codes]
        if (anyNA(lev) || anyDuplicated(lev))
          .jmp_abort("Category levels must be unique and non-missing.", "jmp_metadata_error")
        observed <- unique(values[!is.na(values)])
        if (any(!observed %in% lev))
          .jmp_abort(paste0("Value Order omits observed values in column '", names(d)[i], "'."),
                     "jmp_metadata_error")
        labels <- as.character(lev)
        vl <- m$value_labels
        if (length(vl)) {
          if (length(vl$values) != length(vl$labels) || anyDuplicated(vl$values))
            .jmp_abort("Invalid value-label metadata.", "jmp_metadata_error")
          hit <- match(lev, vl$values)
          labels[!is.na(hit)] <- vl$labels[hit[!is.na(hit)]]
        }
        if (anyNA(labels) || anyDuplicated(labels))
          .jmp_abort("Category labels would merge distinct stored values; conversion stopped.",
                     "jmp_metadata_error")
        d[[i]] <- factor(values, levels = lev, labels = labels, ordered = kind == "ordinal")
        m$stored_values <- stored
        m$r_levels <- lev
        m$r_level_labels <- labels
        m$r_level_order_source <- order_source
      }
    }
    columns[[i]] <- m
  }
  list(data = d, columns = columns, diagnostics = diagnostics)
}
