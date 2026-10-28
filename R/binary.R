# Binary layout derived from JMPReader.jl (Copyright 2024 Jaakko Ruohio)
# and jmp-convert (Copyright 2026 David Mathers), both MIT licensed.
# This is an independent, conservative reader; JMP's binary format is undocumented.

.jmp_corrupt <- function(message) .jmp_abort(message, "jmp_corrupt_error")

.jmp_slice <- function(x, start, n) {
  if (length(start) != 1L || length(n) != 1L || !is.finite(start) ||
      !is.finite(n) || start < 0 || n < 0 || start != floor(start) ||
      n != floor(n) || start + n > length(x))
    .jmp_corrupt("Invalid or truncated binary data range.")
  if (!n) raw() else x[seq.int(start + 1, length.out = n)]
}

.jmp_uint <- function(x, width, signed = FALSE) {
  if (!width %in% c(1L, 2L, 4L, 8L) || length(x) %% width)
    .jmp_corrupt("Invalid integer storage width.")
  if (!length(x)) return(numeric())
  m <- matrix(as.integer(x), nrow = width)
  if (width == 8L && signed) {
    low <- colSums(m[1:4, , drop = FALSE] * 256^(0:3))
    high <- colSums(m[5:8, , drop = FALSE] * 256^(0:3))
    high <- high - (m[8, ] >= 128) * 2^32
    return(low + high * 2^32)
  }
  value <- colSums(m * 256^(seq_len(width) - 1L))
  if (signed) value <- value - (m[width, ] >= 128) * 256^width
  value
}

.jmp_utf8 <- function(x, trailing_nul = FALSE) {
  if (trailing_nul && length(x)) {
    nonzero <- which(x != as.raw(0))
    x <- if (length(nonzero)) x[seq_len(nonzero[length(nonzero)])] else raw()
  }
  if (any(x == as.raw(0))) .jmp_corrupt("Embedded NUL in a text value.")
  s <- rawToChar(x)
  Encoding(s) <- "UTF-8"
  if (is.na(iconv(s, from = "UTF-8", to = "UTF-8", sub = NA)))
    .jmp_abort("Non-UTF-8 text is not supported; bytes are not replaced silently.",
               "jmp_encoding_error")
  s
}

.jmp_find <- function(x, pattern, start = 0) {
  if (start < 0 || start > length(x)) .jmp_corrupt("Invalid search offset.")
  possible <- which(x == pattern[1L]) - 1L
  possible <- possible[possible >= start & possible + length(pattern) <= length(x)]
  for (p in possible) if (identical(.jmp_slice(x, p, length(pattern)), pattern)) return(p)
  .jmp_corrupt("Required binary section marker was not found.")
}

.jmp_cursor <- function(x, pos = 0) {
  e <- new.env(parent = emptyenv())
  e$pos <- pos
  e$take <- function(n) {
    force(n)
    a <- .jmp_slice(x, e$pos, n)
    e$pos <- e$pos + n
    a
  }
  e$skip <- function(n) { e$take(n); invisible(NULL) }
  e$num <- function(w, signed = FALSE) {
    ans <- .jmp_uint(e$take(w), w, signed)
    if (w == 8L && (!is.finite(ans) || abs(ans) > 2^53 - 1))
      .jmp_corrupt("Binary length or offset exceeds exact integer range.")
    ans
  }
  e$str <- function(w) .jmp_utf8(e$take(e$num(w, TRUE)), TRUE)
  e$until <- function(p) { e$pos <- .jmp_find(x, p, e$pos) + length(p); invisible(NULL) }
  e
}

.jmp_header <- function(bytes, max_cells) {
  magic <- as.raw(c(255, 255, 0, 0, 7, 0, 0, 0, 4, 0, 0, 0, 1, 0, 1, 0, 2, 0))
  if (length(bytes) < length(magic) || !identical(bytes[seq_along(magic)], magic))
    .jmp_corrupt("This is not a supported JMP binary data table.")
  p <- .jmp_find(bytes, as.raw(c(7, 0, 8, 0, 0, 0))) - 32
  c <- .jmp_cursor(bytes, p)
  nr <- c$num(8, TRUE)
  nc <- c$num(4, TRUE)
  if (nr < 0 || nc < 0 || nr > max_cells || nc > max_cells || nr * nc > max_cells)
    .jmp_abort("The table dimensions exceed max_cells or are invalid.", "jmp_limit_error")
  if (nc > length(bytes) / 8) .jmp_corrupt("Impossible column count.")
  c$skip(10)
  charset <- c$str(4)
  c$skip(6)
  saved <- readBin(c$take(8), "double", 1L, size = 8L, endian = "little")
  c$skip(2)
  build <- c$str(4)
  table_header_offset <- c$pos
  c$pos <- 2
  repeat {
    c$until(as.raw(c(255, 255)))
    while (c$pos < length(bytes) && bytes[c$pos + 1] == as.raw(255)) c$pos <- c$pos + 1
    c$skip(10)
    visible <- c$num(4)
    hidden <- c$num(4)
    c$skip(8)
    if (visible + hidden == nc) break
    c$pos <- c$pos - 18
  }
  visible_idx <- .jmp_uint(c$take(4 * visible), 4)
  hidden_idx <- .jmp_uint(c$take(4 * hidden), 4)
  widths <- .jmp_uint(c$take(2 * nc), 2)
  c$skip(28)
  repeat {
    b <- as.integer(c$take(2))
    if (b[2] == 255 && b[1] %in% 252:255) c$skip(c$num(8, TRUE))
    else { c$pos <- c$pos - 2; break }
  }
  column_index_offset <- c$pos
  if (c$num(4, TRUE) != nc) .jmp_corrupt("The two column counts disagree.")
  offsets <- vapply(seq_len(nc), function(i) c$num(8, TRUE), numeric(1))
  if (any(offsets < 0 | offsets >= length(bytes)) || any(diff(offsets) <= 0))
    .jmp_corrupt("Invalid or unsorted column offsets.")
  names <- vapply(offsets, function(o) .jmp_cursor(bytes, o)$str(2), character(1))
  list(nrows = nr, ncols = nc, names = names, offsets = offsets, build = build,
       charset = charset, saved_jmp_seconds = saved, widths = widths,
       visible_indices = visible_idx, hidden_indices = hidden_idx,
       table_header_offset = table_header_offset, column_index_offset = column_index_offset)
}

.jmp_table_rows <- function(bytes, info) {
  # Recognize the bounded table-property directory, never search for flag bytes
  # in arbitrary scripts or column data. Unrecognized layouts remain unknown.
  c <- .jmp_cursor(bytes, info$table_header_offset)
  end <- info$column_index_offset
  if (end - c$pos < 20) return(NULL)
  if (c$num(2) != 5 || c$num(4) != 4) return(NULL)
  c$skip(4)
  if (.jmp_uint(.jmp_slice(bytes, c$pos, 2), 2) == 31) {
    c$skip(2)
    size <- c$num(4)
    if (size > end - c$pos - 10) return(NULL)
    c$skip(size)
  }
  count <- c$num(2)
  total <- c$num(8)
  if (c$pos + total != end || count * 10 > total) return(NULL)
  state <- NULL
  seen <- integer()
  for (i in seq_len(count)) {
    if (end - c$pos < 10) return(NULL)
    id <- c$num(2)
    size <- c$num(8)
    if (size > end - c$pos || id %in% seen) return(NULL)
    seen <- c(seen, id)
    if (id == 16) {
      # Each stored row state has eight bytes: color (4), flags (1),
      # marker (2), and a reserved byte (1). Other layouts remain unknown.
      if (size != info$nrows * 8) return(NULL)
      state <- c$take(size)
    } else c$skip(size)
  }
  if (c$pos != end || !65535 %in% seen) return(NULL)
  flags <- if (is.null(state)) rep(0L, info$nrows) else
    as.integer(state[seq.int(5, length.out = info$nrows, by = 8)])
  data.frame(row_id = seq_len(info$nrows),
             excluded = bitwAnd(flags, 2L) != 0L,
             hidden = bitwAnd(flags, 4L) != 0L,
             selected = bitwAnd(flags, 1L) != 0L,
             labelled = bitwAnd(flags, 8L) != 0L)
}

.jmp_properties <- function(bytes, after_dt, end, padding = 4) {
  # This block is only one known header layout. Failure is reported as unknown.
  tryCatch({
    c <- .jmp_cursor(bytes, after_dt)
    c$skip(padding)
    n <- c$num(2)
    total <- c$num(8)
    if (c$pos + total > end || n * 10 > total) return(NULL)
    start <- c$pos
    out <- lapply(seq_len(n), function(i) {
      id <- c$num(2)
      size <- c$num(8)
      if (c$pos + size > start + total) .jmp_corrupt("Invalid column property length.")
      list(id = id, payload = c$take(size))
    })
    if (c$pos - start != total) return(NULL)
    if (anyDuplicated(vapply(out, function(p) p$id, numeric(1)))) return(NULL)
    attr(out, "end_offset") <- c$pos
    out
  }, error = function(e) NULL)
}

.jmp_column_attributes <- function(bytes, pos, end) {
  if (is.null(pos)) return(NULL)
  tryCatch({
    c <- .jmp_cursor(bytes, pos)
    n <- c$num(2)
    total <- c$num(4)
    if (total > end - c$pos || n * 6 > total) return(NULL)
    stop_at <- c$pos + total
    out <- list()
    for (i in seq_len(n)) {
      if (stop_at - c$pos < 6) return(NULL)
      id <- as.character(c$num(2))
      size <- c$num(4)
      if (size > stop_at - c$pos || id %in% names(out)) return(NULL)
      out[[id]] <- c$take(size)
    }
    if (c$pos != stop_at) return(NULL)
    out
  }, error = function(e) NULL)
}

.jmp_literal_column_properties <- function(props, character_column) {
  # Property 7 is an inert length-prefixed JSL property expression, not code
  # to execute. Only complete literal missing-code/value-order declarations
  # are interpreted. Anything else leaves these properties unknown.
  unknown <- list(known = FALSE)
  if (is.null(props)) return(unknown)
  found <- Filter(function(p) p$id == 7, props)
  empty <- list(known = TRUE, missing_value_codes = NULL, value_order = NULL)
  if (!length(found)) return(empty)
  if (length(found) != 1L) return(unknown)
  tryCatch({
    b <- found[[1]]$payload
    c <- .jmp_cursor(b)
    nodes <- list()
    repeat {
      size <- c$num(4, TRUE)
      if (size == -1) break
      if (size < 0 || size > length(b) - c$pos) return(unknown)
      nodes <- c(nodes, .jrp_parse(.jmp_utf8(c$take(size))))
    }
    if (c$pos != length(b)) return(unknown)
    names <- vapply(nodes, function(node) {
      if (node$kind != "call") return("")
      .jrp_name(node$value)
    }, "")
    if (anyDuplicated(names) || any(!names %in% c("missingvaluecodes", "valueorder"))) return(unknown)
    out <- empty
    for (i in seq_along(nodes)) {
      node <- nodes[[i]]
      if (length(node$args) != 1L || !node$args[[1]]$kind %in% c("list", "matrix")) return(unknown)
      value <- .jrp_literal(node$args[[1]])
      if (!length(value)) value <- NULL
      else if (anyNA(value) || (character_column && !is.character(value)) ||
               (!character_column && !is.numeric(value))) return(unknown)
      out[[if (names[i] == "missingvaluecodes") "missing_value_codes" else "value_order"]] <- value
    }
    out
  }, error = function(e) unknown)
}

.jmp_null_strings <- function(x, n) {
  if (n < 0 || n > length(x) + 1) .jmp_corrupt("Invalid string count.")
  zeros <- which(x == as.raw(0))
  if (length(zeros) < n) .jmp_corrupt("Truncated terminated string sequence.")
  ends <- zeros[seq_len(n)]
  starts <- c(0, utils::head(ends, -1L))
  vapply(seq_len(n), function(i) .jmp_utf8(.jmp_slice(x, starts[i], ends[i] - starts[i] - 1)), character(1))
}

.jmp_value_labels <- function(payload, numeric_keys) {
  c <- .jmp_cursor(payload)
  n <- c$num(4)
  keys <- c$take(c$num(4))
  n2 <- c$num(4)
  labels <- c$take(c$num(4))
  if (n != n2 || c$pos != length(payload)) .jmp_corrupt("Malformed value labels.")
  labels <- .jmp_null_strings(labels, n)
  if (numeric_keys) {
    if (length(keys) != 8 * n) .jmp_corrupt("Malformed numeric value labels.")
    values <- readBin(keys, "double", n, size = 8, endian = "little")
  } else values <- .jmp_null_strings(keys, n)
  list(values = values, labels = labels)
}

.jmp_gunzip <- function(x, declared, limit) {
  if (declared < 0 || declared > limit)
    .jmp_abort("Decompressed column exceeds the resource limit.", "jmp_limit_error")
  if (length(x) < 18 || !identical(x[1:3], as.raw(c(31, 139, 8))))
    .jmp_corrupt("Compressed column does not contain a valid gzip header.")
  con <- gzcon(rawConnection(x, "rb"), allowNonCompressed = FALSE)
  on.exit(close(con))
  out <- list()
  total <- 0
  withCallingHandlers({
    repeat {
      chunk <- readBin(con, "raw", n = min(1048576, declared - total + 1))
      if (!length(chunk)) break
      total <- total + length(chunk)
      if (total > declared) .jmp_corrupt("Decompressed size exceeds the column header.")
      out[[length(out) + 1L]] <- chunk
    }
  }, warning = function(w) .jmp_corrupt(paste("Invalid gzip column:", conditionMessage(w))))
  if (total != declared) .jmp_corrupt("Truncated gzip column.")
  do.call(c, c(out, list(raw())))
}

.jmp_numbers <- function(a, width, n) {
  if (!width %in% c(1, 2, 4, 8)) width <- 8
  bytes <- .jmp_slice(a, length(a) - width * n, width * n)
  if (width == 8) {
    v <- readBin(bytes, "double", n, size = 8, endian = "little")
    v[is.nan(v)] <- NA_real_
  } else {
    v <- .jmp_uint(bytes, width, TRUE)
    v[v == -2^(width * 8 - 1) + 1] <- NA_real_
    # R reserves the smallest 32-bit integer for NA: retain doubles in this case.
    if (!any(v == -2147483648, na.rm = TRUE)) v <- as.integer(v)
  }
  v
}

.jmp_temporal <- function(a, b) {
  same <- a == b
  pair <- paste(a, b, sep = ":")
  if ((same && a %in% c(101,102,103,110,111,112,113,114,117,118,122,127,136,139)) ||
      pair %in% c("103:101","111:101","114:101","114:111","114:127","114:128","127:114","136:101","136:122")) return("date")
  if ((b %in% c(105,106,115,116,119,120,126,129) &&
       a %in% c(105,106,108,109,115,116,119,120,121,123,124,125,126,128,129,130,134,135,137,138)) ||
      (same && b %in% c(121,125)) || pair %in% c("119:128","119:127","137:101")) return("datetime")
  if (same && b == 130) return("time")
  if ((same && a %in% c(12,107,108,109,131,132,133)) || pair == "132:121") return("duration")
  NULL
}

.jmp_i64_decimal <- function(x) {
  # Return exact decimal strings rather than rounding integers beyond 2^53.
  vapply(seq_len(length(x) / 8), function(i) {
    b <- as.integer(.jmp_slice(x, (i - 1) * 8, 8))
    neg <- b[8] >= 128
    if (neg) {
      b <- 255 - b
      carry <- 1
      for (j in 1:8) { z <- b[j] + carry; b[j] <- z %% 256; carry <- z %/% 256 }
    }
    digits <- 0
    for (j in 8:1) {
      digits <- digits * 256
      digits[1] <- digits[1] + b[j]
      k <- 1L
      while (k <= length(digits)) {
        carry <- digits[k] %/% 10
        digits[k] <- digits[k] %% 10
        if (carry) {
          if (k == length(digits)) digits <- c(digits, 0)
          digits[k + 1L] <- digits[k + 1L] + carry
        }
        k <- k + 1L
      }
    }
    paste0(if (neg) "-" else "", paste(rev(digits), collapse = ""))
  }, character(1))
}

.jmp_split_strings <- function(bytes, widths) {
  if (any(!is.finite(widths) | widths < 0) || sum(widths) > length(bytes))
    .jmp_corrupt("Invalid string widths.")
  starts <- c(0, utils::head(cumsum(widths), -1L))
  vapply(seq_along(widths), function(i) .jmp_utf8(.jmp_slice(bytes, starts[i], widths[i])), character(1))
}

.jmp_read_column <- function(bytes, info, i, max_cells, budget = NULL) {
  n <- info$nrows
  offset <- info$offsets[i]
  end <- if (i < info$ncols) info$offsets[i + 1L] else length(bytes)
  c <- .jmp_cursor(bytes, offset)
  name <- c$str(2)
  dt <- as.integer(c$take(6))
  after <- c$pos
  props <- .jmp_properties(bytes, after, end, if (dt[1] %in% c(1, 10)) 5 else 4)
  attrs <- .jmp_column_attributes(bytes, attr(props, "end_offset"), end)
  compressed <- dt[1] %in% c(9, 10)
  if (compressed) {
    c$until(as.raw(c(239, 190, 254, 202)))
    compressed_size <- c$num(8)
    unpacked_size <- c$num(8)
    if (c$pos + compressed_size > end) .jmp_corrupt("Compressed data crosses column boundary.")
    if (!is.null(budget)) {
      if (unpacked_size > budget$remaining)
        .jmp_abort("Total decompressed columns exceed 512 MiB.", "jmp_limit_error")
      budget$remaining <- budget$remaining - unpacked_size
    }
    a <- .jmp_gunzip(c$take(compressed_size), unpacked_size,
                    min(536870912, max(1048576, max_cells * 128)))
  } else a <- .jmp_slice(bytes, offset, end - offset)
  width <- function(w) if (w %in% c(1, 2, 4)) w else 8
  meta <- list(name = name, storage_type = NULL, modeling_type = NA_character_,
               format = list(codes = dt[4:5], width = dt[3]), value_labels = NULL,
               properties = list(), formula = NULL, raw_properties = props,
               type_bytes = as.raw(dt), display_width = info$widths[i],
               metadata_complete = FALSE,
               metadata_known = list(modeling_type = FALSE, missing_value_codes = FALSE,
                                     value_order = FALSE, value_labels = !is.null(props),
                                     units = FALSE, formula = FALSE))
  extra <- character()
  if (length(attrs[["23"]]) == 2L) {
    code <- .jmp_uint(attrs[["23"]], 2)
    if (code %in% 0:3) {
      meta$modeling_type <- c("Continuous", "Ordinal", "Nominal", "RowState")[code + 1L]
      meta$metadata_known$modeling_type <- TRUE
    }
  }
  if (dt[1] %in% c(1, 10, 255, 254, 252)) {
    w <- width(if (dt[1] %in% c(255, 254, 252)) dt[5] else dt[6])
    v <- .jmp_numbers(a, w, n)
    meta$storage_type <- if (w == 8) "Float64" else paste0("Int", w * 8)
    kind <- if (dt[1] %in% c(1, 10)) .jmp_temporal(dt[4], dt[5]) else NULL
    if (!is.null(kind)) {
      meta$temporal_kind <- kind
      meta$raw_values <- v
      meta$epoch <- "1904-01-01"
      meta$timezone <- NA_character_
      if (kind == "date") v <- as.Date(floor(v / 86400), origin = "1904-01-01")
      if (kind %in% c("time", "duration")) v <- as.difftime(v, units = "secs")
      if (kind == "datetime") {
        # UTC is a display convention only, not an assertion about the source timezone.
        v <- as.POSIXct(v, origin = "1904-01-01", tz = "UTC")
        extra <- c(extra, "Datetime timezone is unknown; UTC is used only as a display convention. Original seconds are retained.")
      }
    } else if (dt[1] %in% c(1, 10) &&
               !((dt[4] == dt[5] && dt[4] %in% c(0,3,66,67,68,89,96,99,95,81:86)) || dt[5] %in% c(94,99))) {
      extra <- c(extra, "Unrecognized number display format; stored numeric values and format codes retained.")
    }
  } else if (dt[1] == 3 && dt[2] == 3) {
    v <- .jmp_i64_decimal(.jmp_slice(a, length(a) - 8 * n, 8 * n))
    meta$storage_type <- "Int64"
    extra <- c(extra, "64-bit integers are exact decimal strings to avoid R double precision loss.")
  } else if (dt[1] == 9 && dt[2] == 3) {
    markers <- c("\u2022", "+", "X", "\u25a1", "\u25ca", "\u25b3", "Y", "Z", "\u25ef", "\u25ad", "\u25af", "*", "\u26ab", "\u25ac", "\u25ae", "\u25a0", "\u29eb", "\u25bd", "\u25c1", "\u25b7", "\u25b2", "\u25bc", "\u25c0", "\u25b6", "\u2227", "\u2228", "<", ">", "\u2223", "\u2500", "/", "\\")
    colors <- c("000000","555555","787878","C0C0C0","FFFFFF","A00922","C91629","F03246","FF5C76","FF98A6","904700","BC5B03","E57406","FF9138","FFB17D","706F00","AFA502","DAD109","F0E521","FFF977","516A00","729400","90BF04","A2DC06","C1FF3D","00670C","11981B","21BC2D","23E72E","6AFF6B","007254","019970","04C791","06E3AA","0FFFBC","006D71","01989C","0CBCBC","06E2E3","67FFF7","00638F","0380B4","05A1D2","08C5F7","75E4FF","034AB0","0557D6","2867FD","4E9CFF","7E89FF","6A02A7","8C05CF","AB08FC","C170FF","D29AFF","930195","B803B9","DC06E1","FA50FF","FD96FF","9D0170","C5048D","E906A4","FF49BC","FF8CCD")
    if (dt[5] < 7) .jmp_corrupt("Invalid row state width.")
    state <- lapply(seq_len(n), function(r) {
      b <- as.integer(.jmp_slice(a, (r - 1) * dt[5], 7))
      idx <- b[6] + 256 * b[7]
      marker <- if (idx < length(markers)) markers[idx + 1] else intToUtf8(idx)
      color <- if (b[4] == 255) paste(sprintf("%02X", b[3:1]), collapse = "") else {
        if (b[1] >= length(colors)) .jmp_abort("Unknown row state palette index.", "jmp_unsupported_error")
        colors[b[1] + 1]
      }
      c(marker = marker, color = paste0("#", color))
    })
    meta$row_states <- data.frame(marker = vapply(state, `[[`, "", "marker"),
                                  color = vapply(state, `[[`, "", "color"), stringsAsFactors = FALSE)
    meta$raw_row_states <- a
    meta$storage_type <- "RowState"
    v <- paste(meta$row_states$marker, meta$row_states$color)
    extra <- c(extra, "Row-state column marker/color decoded; other state bits retained as raw bytes, not interpreted.")
  } else if (dt[1] %in% c(2, 9) && dt[2] %in% c(1, 2)) {
    meta$storage_type <- "Character"
    pool_prop <- Filter(function(p) p$id == 4, props)
    if (dt[3] == 0 && dt[4] == 0 && dt[5] %in% c(1,2,4) && length(pool_prop)) {
      p <- .jmp_cursor(pool_prop[[1]]$payload)
      np <- p$num(2)
      pool <- .jmp_null_strings(p$take(length(pool_prop[[1]]$payload) - p$pos), np)
      idx <- .jmp_uint(.jmp_slice(a, length(a) - n * dt[5], n * dt[5]), dt[5])
      bad <- idx >= length(pool)
      if (any(bad & idx != 256^dt[5] - 1)) .jmp_corrupt("Invalid coded string index.")
      v <- rep("", n)
      v[!bad] <- pool[idx[!bad] + 1]
    } else if ((dt[3] == 0 && dt[4] == 0 && dt[5] > 0) || (dt[3] %in% 1:7 && dt[4] == 0)) {
      w <- dt[5]
      if (!w && n) .jmp_corrupt("Zero fixed string width.")
      data <- .jmp_slice(a, length(a) - n * w, n * w)
      v <- vapply(seq_len(n), function(r) {
        s <- .jmp_slice(data, (r - 1) * w, w)
        zero <- which(s == as.raw(0))
        if (length(zero)) s <- .jmp_slice(s, 0, zero[1] - 1)
        .jmp_utf8(s)
      }, character(1))
    } else if (all(dt[3:5] == 0)) {
      if (compressed) {
        p <- .jmp_cursor(a)
        if (p$num(8, TRUE) == length(a)) {
          p$skip(9)
          p$num(8, TRUE)
          w <- p$num(1, TRUE)
          if (!w %in% c(1,2,4)) .jmp_corrupt("Unknown compact string index width.")
          idx <- .jmp_uint(p$take(w * n), w)
          np <- max(c(0, idx))
          if (np > n || np > length(a)) .jmp_corrupt("Invalid compact string pool count.")
          lw <- p$num(1, TRUE)
          if (!lw %in% c(1,2)) .jmp_corrupt("Unknown compact string length width.")
          pool <- vapply(seq_len(np), function(k) .jmp_utf8(p$take(p$num(lw, TRUE))), character(1))
          v <- rep("", n)
          v[idx > 0] <- pool[idx[idx > 0]]
        } else {
          w <- as.integer(.jmp_slice(a, 8, 1))
          if (!w %in% c(1,2)) .jmp_corrupt("Unknown compressed string length width.")
          widths <- .jmp_uint(.jmp_slice(a, 13, n * w), w, TRUE)
          v <- .jmp_split_strings(.jmp_slice(a, 13 + n * w, length(a) - 13 - n * w), widths)
        }
      } else {
        p <- .jmp_cursor(bytes, after)
        p$skip(6)
        p$skip(p$num(8, TRUE))
        p$skip(2)
        p$skip(p$num(4) + 8)
        w <- p$num(1)
        p$num(4)
        if (!w %in% c(1,2,4)) .jmp_corrupt("Unknown string length width.")
        widths <- .jmp_uint(p$take(w * n), w, TRUE)
        total <- sum(widths)
        if (any(widths < 0) || total > end - offset) .jmp_corrupt("Invalid string data size.")
        v <- .jmp_split_strings(.jmp_slice(bytes, end - total, total), widths)
      }
    } else .jmp_abort(paste("Unsupported string layout in", name), "jmp_unsupported_error")
  } else .jmp_abort(paste("Unsupported binary column type in", name,
                          paste(sprintf("%02x", dt), collapse = ":")), "jmp_unsupported_error")
  labels <- Filter(function(p) p$id == 14, props)
  if (length(labels)) {
    meta$value_labels <- tryCatch(.jmp_value_labels(labels[[1]]$payload,
      !identical(meta$storage_type, "Character")), error = function(e) {
        .jmp_abort(paste("Cannot decode value labels in", name, ":", conditionMessage(e)), "jmp_unsupported_error")
      })
  }
  literal <- if (is.null(attrs)) list(known = FALSE) else
    .jmp_literal_column_properties(props, identical(meta$storage_type, "Character"))
  if (isTRUE(literal$known)) {
    meta$missing_value_codes <- literal$missing_value_codes
    meta$value_order <- literal$value_order
    meta$metadata_known$missing_value_codes <- TRUE
    meta$metadata_known$value_order <- TRUE
  }
  if (!meta$metadata_known$modeling_type)
    extra <- c(extra, "Modeling type is unavailable or unsupported; it was not inferred from storage type.")
  if (!meta$metadata_known$missing_value_codes)
    extra <- c(extra, "Missing-value definitions and value order could not be fully interpreted; no absence was assumed.")
  if (identical(meta$modeling_type, "Ordinal") && !length(meta$value_order))
    extra <- c(extra, "Ordinal modeling type is retained, but category order is not explicit; ordered-factor conversion will not guess an order.")
  list(values = v, metadata = meta, messages = extra)
}

.read_jmp_binary <- function(bytes, max_cells = 1e7) {
  info <- .jmp_header(bytes, max_cells)
  rows <- .jmp_table_rows(bytes, info)
  budget <- new.env(parent = emptyenv())
  budget$remaining <- 536870912
  columns <- lapply(seq_len(info$ncols), function(i) .jmp_read_column(bytes, info, i, max_cells, budget))
  data <- lapply(columns, `[[`, "values")
  names(data) <- info$names
  data <- structure(data, class = "data.frame", row.names = .set_row_names(info$nrows))
  meta <- lapply(columns, `[[`, "metadata")
  names(meta) <- info$names
  diagnostics <- data.frame(code = "binary_metadata_partial", scope = "table",
    message = "Binary reader retains supported modeling types, literal missing-code definitions, storage, format and value-label metadata. Units, formulas, table scripts and other properties are not fully decoded; check each column's metadata_known flags.",
    stringsAsFactors = FALSE)
  if (is.null(rows)) diagnostics <- rbind(diagnostics, data.frame(
    code = "table_row_states_unavailable", scope = "rows",
    message = "Table row-state layout is unsupported. Exclusion, hidden and selection states are unknown; row-state columns are separate."))
  for (i in seq_along(columns)) for (m in columns[[i]]$messages)
    diagnostics <- rbind(diagnostics, data.frame(code = "representation", scope = info$names[i], message = m, stringsAsFactors = FALSE))
  list(data = data, columns = meta, rows = rows,
       table = info[c("build", "charset", "saved_jmp_seconds", "nrows", "ncols", "visible_indices", "hidden_indices")],
       scripts = list(), diagnostics = diagnostics)
}
