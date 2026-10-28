# A deliberately small JSL reader. This file never executes JSL or R code.
# The accepted grammar is described in README.md; unsupported input is an error.

.jrp_name <- function(x) gsub("[[:space:]_]", "", tolower(x))

.jrp_error <- function(message, subclass = "jrp_syntax_error", position = NULL) {
  if (!is.null(position)) message <- paste0(message, " (character ", position, ")")
  .jmp_abort(message, subclass = subclass)
}

.jrp_lex <- function(text) {
  n <- nchar(text, type = "chars")
  if (n > 16000000L) .jrp_error("JRP text exceeds the 16 million character limit.", "jmp_resource_error")
  z <- strsplit(text, "", fixed = TRUE)[[1L]]
  out <- vector("list", min(n + 1L, 10000L))
  nt <- 0L
  emit <- function(type, value, start, end) {
    nt <<- nt + 1L
    if (nt > 1000000L) .jrp_error("JRP token limit exceeded.", "jmp_resource_error", start)
    out[[nt]] <<- list(type = type, value = value, start = start, end = end)
  }
  i <- 1L
  while (i <= n) {
    c <- z[[i]]
    if (grepl("[[:space:]]", c)) { i <- i + 1L; next }
    if (c == "/" && i < n && z[[i + 1L]] == "/") {
      i <- i + 2L
      while (i <= n && !z[[i]] %in% c("\n", "\r")) i <- i + 1L
      next
    }
    if (c == "/" && i < n && z[[i + 1L]] == "*") {
      start <- i
      i <- i + 2L
      while (i < n && !(z[[i]] == "*" && z[[i + 1L]] == "/")) i <- i + 1L
      if (i >= n) .jrp_error("Unterminated block comment.", position = start)
      i <- i + 2L
      next
    }
    if (c == '"') {
      start <- i
      i <- i + 1L
      value <- character()
      run <- i
      while (i <= n && z[[i]] != '"') {
        if (z[[i]] == "\\" && i + 1L <= n && z[[i + 1L]] == "!") {
          if (i > run) value <- c(value, substr(text, run, i - 1L))
          if (i + 2L > n) .jrp_error("Incomplete JSL string escape.", position = i)
          escape <- z[[i + 2L]]
          replacement <- switch(escape, n = "\n", N = "\n", r = "\r", R = "\r",
                                t = "\t", T = "\t", '"' = '"', "\\" = "\\", NULL)
          if (is.null(replacement)) .jrp_error("Unsupported JSL string escape.", position = i)
          value <- c(value, replacement)
          i <- i + 3L
          run <- i
        } else i <- i + 1L
      }
      if (i > n) .jrp_error("Unterminated quoted string.", position = start)
      if (i > run) value <- c(value, substr(text, run, i - 1L))
      emit("string", paste0(value, collapse = ""), start, i)
      i <- i + 1L
      next
    }
    if (grepl("[0-9]", c) || (c == "." && i < n && grepl("[0-9]", z[[i + 1L]]))) {
      start <- i
      tail <- substr(text, i, min(n, i + 127L))
      number <- regmatches(tail, regexpr("^(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?", tail, perl = TRUE))
      i <- i + nchar(number)
      val <- suppressWarnings(as.numeric(number))
      if (!is.finite(val)) .jrp_error("Non-finite numeric literal is not supported.", position = start)
      emit("number", val, start, i - 1L)
      next
    }
    if (grepl("[[:alpha:]_]", c)) {
      start <- i
      i <- i + 1L
      while (i <= n && grepl("[[:alnum:]_ ]", z[[i]])) i <- i + 1L
      value <- trimws(substr(text, start, i - 1L))
      emit("ident", value, start, i - 1L)
      next
    }
    if (c %in% strsplit("()[]{},;=.+-*/:^<>!|&", "", fixed = TRUE)[[1L]]) {
      emit(c, c, i, i)
      i <- i + 1L
      next
    }
    .jrp_error(paste0("Unsupported character '", c, "'."), position = i)
  }
  out <- out[seq_len(nt)]
  out[[nt + 1L]] <- list(type = "eof", value = "", start = n + 1L, end = n + 1L)
  out
}

.jrp_parse <- function(text) {
  tokens <- .jrp_lex(text)
  # Scan call tokens, not raw strings: comments and quoted 'Open(...)' are data.
  external <- c("open", "include", "loadtextfile", "loadfile", "importdata",
                "opendatabase", "newsqlquery", "sqlquery", "newhttprequest",
                "httprequest", "downloadfile", "rsendfile", "pythonimport")
  dynamic <- c("eval", "evalexpr", "parse", "function", "for", "foreach", "while",
               "if", "runprogram", "runscript", "execute", "wait", "schedule",
               "pythonsubmit", "pythonsubmitfile", "rsubmit", "rsubmitfile",
               "randomnormal", "randomuniform")
  if (length(tokens) > 1L) for (k in seq_len(length(tokens) - 1L)) {
    if (tokens[[k]]$type == "ident" && tokens[[k + 1L]]$type == "(") {
      name <- .jrp_name(tokens[[k]]$value)
      if (name %in% external) .jrp_error(paste0("External data/reference call is not allowed: ", tokens[[k]]$value, "()."), "jrp_external_reference_error", tokens[[k]]$start)
      if (name %in% dynamic) .jrp_error(paste0("Dynamic JSL is not allowed: ", tokens[[k]]$value, "()."), "jrp_dynamic_error", tokens[[k]]$start)
    }
  }
  p <- 1L
  peek <- function() tokens[[p]]
  take <- function(type = NULL) {
    token <- peek()
    if (!is.null(type) && token$type != type) .jrp_error(paste0("Expected '", type, "', found '", token$type, "'."), position = token$start)
    p <<- p + 1L
    token
  }
  node <- function(kind, value = NULL, args = NULL, start, end) list(kind = kind, value = value, args = args, start = start, end = end)
  expression <- NULL
  collection <- function(close, depth) {
    args <- list()
    if (peek()$type == close) { take(close); return(args) }
    repeat {
      args[[length(args) + 1L]] <- expression(depth + 1L)
      if (peek()$type == close) { take(close); break }
      take(",")
      if (peek()$type == close) .jrp_error("Trailing commas are not supported.", position = peek()$start)
    }
    args
  }
  expression <- function(depth = 0L) {
    if (depth > 64L) .jrp_error("JRP nesting limit exceeded.", "jmp_resource_error", peek()$start)
    token <- take()
    if (token$type %in% c("number", "string")) {
      x <- node(token$type, token$value, start = token$start, end = token$end)
    } else if (token$type == ".") {
      x <- node("number", NA_real_, start = token$start, end = token$end)
    } else if (token$type %in% c("+", "-")) {
      value <- take("number")
      x <- node("number", if (token$type == "-") -value$value else value$value, start = token$start, end = value$end)
    } else if (token$type %in% c("[", "{")) {
      close <- if (token$type == "[") "]" else "}"
      args <- collection(close, depth)
      x <- node(if (token$type == "[") "matrix" else "list", args = args, start = token$start, end = tokens[[p - 1L]]$end)
    } else if (token$type == "ident") {
      if (peek()$type != "(") {
        x <- node("symbol", token$value, start = token$start, end = token$end)
      } else {
        take("(")
        if (.jrp_name(token$value) == "formula") {
          # Formula source is retained without interpretation. Only stored Values
          # can supply data. Bracket balancing still validates its container.
          first <- peek()$start
          formula_start <- p
          stack <- ")"
          while (length(stack)) {
            t <- take()
            if (t$type == "eof") .jrp_error("Unterminated Formula().", position = token$start)
            if (t$type %in% c("(", "[", "{")) {
              stack <- c(stack, switch(t$type, "(" = ")", "[" = "]", "{" = "}"))
              if (length(stack) + depth > 64L) .jrp_error("JRP nesting limit exceeded.", "jmp_resource_error", t$start)
            } else if (t$type %in% c(")", "]", "}")) {
              if (t$type != stack[[length(stack)]]) .jrp_error("Mismatched Formula() delimiter.", position = t$start)
              stack <- head(stack, -1L)
            }
          }
          formula_tokens <- tokens[seq.int(formula_start, p - 1L)]
          safe_formula_calls <- c("abs", "sqrt", "log", "log10", "exp", "power", "round",
                                  "floor", "ceiling", "min", "max", "sum", "mean")
          for (fi in seq_along(formula_tokens)) {
            ft <- formula_tokens[[fi]]
            if (ft$type %in% c(";", "=")) .jrp_error("Assignments or statements inside Formula() are not supported.", "jrp_dynamic_error", ft$start)
            if (ft$type == "ident" && fi < length(formula_tokens) &&
                formula_tokens[[fi + 1L]]$type == "(" && !.jrp_name(ft$value) %in% safe_formula_calls) {
              .jrp_error("Unsupported function inside Formula(); only simple arithmetic formula source is accepted.", "jrp_dynamic_error", ft$start)
            }
          }
          x <- node("formula", substr(text, first, t$start - 1L), start = token$start, end = t$end)
        } else {
          args <- collection(")", depth)
          x <- node("call", token$value, args, token$start, tokens[[p - 1L]]$end)
        }
      }
    } else .jrp_error("Expected a literal value or a supported declaration.", "jrp_dynamic_error", token$start)
    if (peek()$type == "=") {
      take("=")
      rhs <- expression(depth + 1L)
      x <- node("pair", args = list(x, rhs), start = x$start, end = rhs$end)
    }
    x
  }
  result <- list()
  while (peek()$type != "eof") {
    result[[length(result) + 1L]] <- expression()
    if (peek()$type == ";") take(";")
    else if (peek()$type != "eof") .jrp_error("Unexpected trailing or dynamic JSL expression.", "jrp_dynamic_error", peek()$start)
  }
  result
}

.jrp_literal <- function(x, descriptors = FALSE) {
  if (x$kind %in% c("number", "string")) return(x$value)
  if (x$kind %in% c("matrix", "list")) {
    values <- lapply(x$args, .jrp_literal, descriptors = descriptors)
    if (!length(values)) return(if (x$kind == "matrix") numeric() else list())
    scalar <- vapply(values, function(v) is.atomic(v) && length(v) == 1L, logical(1))
    kinds <- vapply(values, typeof, character(1))
    if (all(scalar) && length(unique(kinds)) == 1L) return(unlist(values, use.names = FALSE))
    return(values)
  }
  if (x$kind == "pair") return(list(key = .jrp_literal(x$args[[1L]], descriptors), value = .jrp_literal(x$args[[2L]], descriptors)))
  descriptor_names <- c("lsl", "usl", "target", "showlimits", "commonorder", "roworderlevels",
                        "reverseorder", "customorder", "valueorder", "color", "min", "max", "inc")
  if (descriptors && x$kind == "call" && .jrp_name(x$value) %in% descriptor_names) {
    return(list(jsl_call = x$value, arguments = lapply(x$args, .jrp_literal, descriptors = TRUE)))
  }
  .jrp_error("A value requires dynamic or unsupported JSL; only literals are accepted.", "jrp_dynamic_error", x$start)
}

.jrp_labels <- function(x) {
  if (!x$kind %in% c("list", "matrix") || !all(vapply(x$args, function(a) a$kind == "pair", logical(1)))) {
    .jrp_error("Value Labels must use literal code = label pairs.", "jrp_dynamic_error", x$start)
  }
  codes <- lapply(x$args, function(a) .jrp_literal(a$args[[1L]]))
  labels <- lapply(x$args, function(a) .jrp_literal(a$args[[2L]]))
  if (any(!vapply(codes, function(v) is.atomic(v) && length(v) == 1L, logical(1))) ||
      any(!vapply(labels, function(v) is.character(v) && length(v) == 1L, logical(1)))) {
    .jrp_error("Value labels require scalar codes and character labels.", position = x$start)
  }
  if (length(unique(vapply(codes, typeof, character(1)))) > 1L) .jrp_error("Value label codes must have one type.", position = x$start)
  codes <- unlist(codes, use.names = FALSE)
  if (anyDuplicated(codes)) .jrp_error("Duplicate value label codes.", position = x$start)
  list(values = codes, labels = unlist(labels, use.names = FALSE))
}

.read_jrp_text <- function(text, max_cells = 1e7) {
  declarations <- .jrp_parse(text)
  table <- NULL
  for (d in declarations) {
    if (d$kind == "call" && .jrp_name(d$value) == "namesdefaulttohere" &&
        length(d$args) == 1L && identical(.jrp_literal(d$args[[1L]]), 1)) next
    if (d$kind == "pair" && d$args[[1L]]$kind == "symbol") d <- d$args[[2L]]
    if (d$kind != "call" || .jrp_name(d$value) != "newtable") .jrp_error("Only one literal New Table() declaration is supported; report or dynamic commands are not executed.", "jrp_dynamic_error", d$start)
    if (!is.null(table)) .jrp_error("Multiple embedded tables are not yet supported.", "jmp_unsupported_error", d$start)
    table <- d
  }
  if (is.null(table)) .jrp_error("No embedded New Table() data were found.", "jmp_unsupported_error")
  if (!length(table$args) || table$args[[1L]]$kind != "string") .jrp_error("New Table() requires a literal table name.", "jrp_dynamic_error", table$start)
  table_name <- table$args[[1L]]$value
  row_count <- NULL
  columns <- list()
  values <- list()
  table_properties <- list()
  diagnose <- list()
  diagnostic <- function(code, scope, message) {
    diagnose[[length(diagnose) + 1L]] <<- data.frame(code = code, scope = scope, message = message, stringsAsFactors = FALSE)
  }
  call_name <- function(x) if (x$kind == "call") .jrp_name(x$value) else ""
  for (a in table$args[-1L]) {
    name <- call_name(a)
    if (name == "addrows") {
      if (!is.null(row_count) || length(a$args) != 1L) .jrp_error("Add Rows() must occur once with one integer.", position = a$start)
      row_count <- .jrp_literal(a$args[[1L]])
      if (!is.numeric(row_count) || length(row_count) != 1L || is.na(row_count) ||
          !is.finite(row_count) || row_count < 0 || row_count != floor(row_count)) .jrp_error("Invalid Add Rows() count.", position = a$start)
      if (row_count > max_cells) .jrp_error("JRP row count exceeds max_cells.", "jmp_resource_error", a$start)
    } else if (name == "newcolumn") {
      if (!length(a$args) || a$args[[1L]]$kind != "string") .jrp_error("New Column() requires a literal name.", "jrp_dynamic_error", a$start)
      cn <- a$args[[1L]]$value
      if (!nzchar(cn) || cn %in% names(columns)) .jrp_error("Empty or duplicate column names are not supported.", position = a$start)
      meta <- list(name = cn, storage_type = "numeric", modeling_type = "Continuous", format = NULL,
                   value_labels = NULL, missing_value_codes = NULL, value_order = NULL,
                   metadata_known = list(modeling_type = TRUE, missing_value_codes = TRUE,
                                         value_order = TRUE, value_labels = TRUE),
                   properties = list(), formula = NULL, raw_properties = list())
      v <- NULL
      have_values <- FALSE
      seen <- character()
      for (b in a$args[-1L]) {
        bn <- call_name(b)
        if (b$kind %in% c("symbol", "string")) {
          word <- .jrp_name(b$value)
          if (word %in% c("numeric", "character")) {
            if ("type" %in% seen) .jrp_error("Duplicate column storage type.", position = b$start)
            seen <- c(seen, "type")
            meta$storage_type <- word
          } else if (word %in% c("continuous", "nominal", "ordinal")) {
            if ("model" %in% seen) .jrp_error("Duplicate modeling type.", position = b$start)
            seen <- c(seen, "model")
            meta$modeling_type <- paste0(toupper(substr(word, 1L, 1L)), substring(word, 2L))
          } else .jrp_error("Unsupported column declaration.", "jrp_dynamic_error", b$start)
        } else if (bn %in% c("values", "setvalues")) {
          if (have_values || length(b$args) != 1L) .jrp_error("Each column requires one Values() or Set Values() argument.", position = b$start)
          v <- .jrp_literal(b$args[[1L]])
          if (is.list(v) && !length(v)) v <- character()
          if (!is.atomic(v) || is.null(v)) .jrp_error("Column values must be a homogeneous literal vector.", "jrp_dynamic_error", b$start)
          have_values <- TRUE
        } else if (bn == "format") {
          if (!is.null(meta$format)) .jrp_error("Duplicate Format().", position = b$start)
          meta$format <- lapply(b$args, .jrp_literal)
        } else if (bn == "setproperty") {
          if (length(b$args) != 2L || b$args[[1L]]$kind != "string") .jrp_error("Set Property() requires a literal name and value.", "jrp_dynamic_error", b$start)
          property_name <- b$args[[1L]]$value
          if (.jrp_name(property_name) %in% .jrp_name(names(meta$properties))) .jrp_error("Duplicate column property.", position = b$start)
          meta$properties[[property_name]] <- .jrp_literal(b$args[[2L]], descriptors = TRUE)
          if (.jrp_name(property_name) == "valuelabels") {
            if (!is.null(meta$value_labels)) .jrp_error("Duplicate Value Labels property.", position = b$start)
            meta$value_labels <- .jrp_labels(b$args[[2L]])
          }
          if (.jrp_name(property_name) == "missingvaluecodes") {
            meta$missing_value_codes <- .jrp_literal(b$args[[2L]])
            if (!is.atomic(meta$missing_value_codes) && length(meta$missing_value_codes)) .jrp_error("Missing Value Codes must be a literal vector.", position = b$start)
          }
          if (.jrp_name(property_name) %in% c("valueorder", "valueordering")) {
            meta$value_order <- .jrp_literal(b$args[[2L]], descriptors = TRUE)
            if (is.list(meta$value_order) && length(meta$value_order)) meta$metadata_known$value_order <- FALSE
          }
        } else if (bn == "valuelabels") {
          if (length(b$args) != 1L || !is.null(meta$value_labels)) .jrp_error("Unsupported or duplicate Value Labels().", position = b$start)
          meta$value_labels <- .jrp_labels(b$args[[1L]])
          meta$properties[["Value Labels"]] <- .jrp_literal(b$args[[1L]])
        } else if (b$kind == "formula") {
          if (!is.null(meta$formula)) .jrp_error("Duplicate Formula().", position = b$start)
          meta$formula <- b$value
        } else if (bn %in% c("setselected", "setdisplaywidth", "setfieldwidth", "usevaluelabels", "label", "hide", "exclude", "lock")) {
          if (length(b$args) != 1L) .jrp_error("Unsupported column attribute arguments.", position = b$start)
          meta$properties[[b$value]] <- .jrp_literal(b$args[[1L]])
        } else .jrp_error("Unsupported or dynamic New Column() argument.", "jrp_dynamic_error", b$start)
      }
      if (!"model" %in% seen && meta$storage_type == "character") meta$modeling_type <- "Nominal"
      if (!have_values) .jrp_error(paste0("Column '", cn, "' has no stored literal Values(); computing its data is not allowed."), "jrp_dynamic_error", a$start)
      if (meta$storage_type == "numeric" && !is.numeric(v)) .jrp_error(paste0("Numeric column '", cn, "' contains nonnumeric values."), position = a$start)
      if (meta$storage_type == "character" && !is.character(v)) .jrp_error(paste0("Character column '", cn, "' contains noncharacter values."), position = a$start)
      if (length(v) > max_cells || sum(vapply(values, length, numeric(1))) + length(v) > max_cells) .jrp_error("JRP data exceed max_cells.", "jmp_resource_error", a$start)
      if (!is.null(meta$formula)) diagnostic("formula_not_evaluated", cn, "Stored values were imported; the JSL formula was retained without evaluation.")
      if (!is.null(meta$format)) diagnostic("format_preserved", cn, "JSL display format was retained; raw stored values were not reformatted or converted to dates.")
      columns[[cn]] <- meta
      values[[cn]] <- v
    } else if (name %in% c("setproperty", "settablevariable")) {
      if (length(a$args) != 2L || a$args[[1L]]$kind != "string") .jrp_error("Table properties require a literal name and value.", "jrp_dynamic_error", a$start)
      key <- a$args[[1L]]$value
      if (key %in% names(table_properties)) .jrp_error("Duplicate table property.", position = a$start)
      table_properties[[key]] <- .jrp_literal(a$args[[2L]], descriptors = TRUE)
    } else .jrp_error("Unsupported or dynamic New Table() argument.", "jrp_dynamic_error", a$start)
  }
  lengths <- vapply(values, length, numeric(1))
  if (is.null(row_count)) row_count <- if (length(lengths)) lengths[[1L]] else 0
  if (length(lengths) && any(lengths != row_count)) .jrp_error("Stored column lengths and Add Rows() do not agree; implicit filling is not supported.")
  if (row_count * max(length(columns), 1L) > max_cells) .jrp_error("JRP data exceed max_cells.", "jmp_resource_error")
  data <- structure(values, class = "data.frame", row.names = if (row_count) c(NA_integer_, -as.integer(row_count)) else integer())
  diagnostic("jrp_literal_subset", "table", "Only literal embedded table declarations were read. No JSL was executed.")
  # The accepted grammar has no state-setting statement. A new table starts
  # with no excluded/hidden/selected/labelled rows. State setters are rejected.
  rows <- data.frame(row_id = seq_len(row_count), excluded = rep(FALSE, row_count),
                     hidden = rep(FALSE, row_count), selected = rep(FALSE, row_count),
                     labelled = rep(FALSE, row_count), stringsAsFactors = FALSE)
  list(data = data, columns = columns, rows = rows,
       table = list(name = table_name, properties = table_properties),
       scripts = list(jsl_source = text), diagnostics = do.call(rbind, diagnose))
}
