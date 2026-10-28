library(jmp2r)

# Real JMP files and expected values originate in JMPReader.jl's MIT test suite.
fixture_dir <- system.file("extdata", "upstream", package = "jmp2r")
stopifnot(nzchar(fixture_dir))
read_fixture <- function(name) read_jmp(file.path(fixture_dir, name), metadata = "quiet")
expect_error_class <- function(expr, cls) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, cls))
}
same <- function(x, y) stopifnot(isTRUE(all.equal(x, y, check.attributes = FALSE)))
internal <- function(n) getFromNamespace(n, "jmp2r")

files <- list.files(fixture_dir, "\\.jmp$", full.names = TRUE)
stopifnot(length(files) >= 19L)
for (f in files) {
  x <- read_jmp(f, metadata = "quiet")
  stopifnot(inherits(x, "jmp_dataset"), ncol(x$data) == length(x$columns),
            all(lengths(x$data) == nrow(x$data)), nrow(x$rows) == nrow(x$data),
            !any(x$rows$excluded),
            !"table_row_states_unavailable" %in% x$diagnostics$code,
            identical(x$source$bytes, readBin(f, "raw", file.info(f)$size)))
}

x <- read_fixture("example1.jmp")
d <- x$data
same(d$ints, 1:4)
same(d$floats, c(11.1,22.2,33.3,44.4))
same(d$charconstwidth, letters[1:4])
same(format(d$time[1:3], tz = "UTC", format = "%Y-%m-%d %H:%M:%S"),
     c("1976-04-01 21:12:00", "1984-08-06 23:58:00", "2003-06-02 17:00:00"))
stopifnot(is.na(d$time[4]), inherits(d$time, "POSIXct"),
          is.na(x$columns$time$timezone), length(x$columns$time$raw_values) == 4L)
same(as.character(d$date), c("2024-01-13", "2024-01-14", NA, "2032-02-12"))
same(as.numeric(d$duration, units = "secs"), c(2322,364,229,0))
same(d$charconstwidth2, c("a","bb","ccc","dddd"))
same(d$charvariable16, c("aa","bbbb","cccccccc",strrep("abcdefghij",13)))
same(d$formula, c("2","4","6","8"))
same(d$pressures, c(101.325,NA,2.6,4.63309e110))
same(d[["char utf8"]], c("\ua66e\ua66e\ua66e","\U0001f6b4\U0001f4a8","j\u00e4\u00e4\u00e4\u00e4r","\u8f9b\u53e3"))
same(d$charvariable8, c("a","bb","cc","abcdefghijkl"))
stopifnot(identical(as.data.frame(x), d), x$columns$ints$metadata_known$modeling_type,
          x$columns$ints$modeling_type == "Continuous",
          x$columns$ints$metadata_known$missing_value_codes,
          is.null(x$columns$ints$missing_value_codes))
expect_error_class(as_analysis_data(x, factors = TRUE), "jmp_metadata_error")
expect_error_class(as_analysis_data(x, missing_codes = TRUE), "jmp_metadata_error")
stopifnot(identical(as_analysis_data(x, exclude_rows = TRUE), x$data))

x <- read_fixture("compressed.jmp")$data
stopifnot(nrow(x) == 10000L, all(x$numeric == 1), all(x$character1 == "a"),
          all(x$character11 == "abcdefghijk"), all(x$character130 == strrep("abcdefghij",13)),
          all(format(x[["y-m-d h:m:s"]], tz="UTC", format="%Y-%m-%d %H:%M:%S") == "1904-01-01 00:00:01"),
          all(as.character(x[["yyyy-mm-dd"]]) == "2024-01-20"),
          all(as.numeric(x[["min:s"]], units="secs") == 196))
same(as.character(read_fixture("date.jmp")$data$ddmmyyyy),
     c("2011-05-25","1973-05-24","2027-05-22","2020-05-01"))
same(as.numeric(read_fixture("duration.jmp")$data[[":day:hr:m:s"]], units="secs"), rep(88201,3))
x <- read_fixture("time.jmp")$data
stopifnot(ncol(x) == 20L)
for (col in x) same(format(col, tz="UTC", format="%Y-%m-%d %H:%M:%S"),
                    c("1914-04-27 19:54:14","1978-01-07 06:11:24"))

x <- read_fixture("longcolumnnames.jmp")$data
same(names(x), c(paste(sprintf("%010d",1:140),collapse=""), paste(sprintf("%010d",1:280),collapse="")))
same(x[[1]], rep(1,3)); same(x[[2]], rep(2,3))
x <- read_fixture("singlecolumnsinglerow.jmp")$data
stopifnot(identical(dim(x), c(1L,1L)), names(x) == "Column 1", x[[1]] == 1)

x <- read_fixture("byteintegers.jmp")$data
same(x[["1-byte integer"]],c(0,1,0,1,0))
same(x[["2-byte integer"]],c(-187,-30,-18,13,-55))
same(x[["4-byte integer"]],c(-28711,-16887,-26063,13093,-44761))
x <- read_fixture("byteintegers_withmissing.jmp")$data
same(x[["1-byte integer"]],c(0,1,0,1,0,NA))
same(x[["2-byte integer"]],c(-187,-30,-18,13,-55,NA))
same(x[["4-byte integer"]],c(-28711,-16887,-26063,13093,-44761,NA))
x <- read_fixture("byteintegers_notcompressed.jmp")$data
same(x$onebyte,c(1,2,-126,127)); same(x$twobyte,c(32767,NA,0,-32766))
same(x$fourbyte,c(NA,2147483647,-2147483646,NA)); same(x$numeric,c(NA,2147483648,NA,NA))
x <- read_fixture("geographic.jmp")$data
same(x$Longitude_DDD,c(151.2099,24.945831,-122.449))
stopifnot(is.na(x$Latitude_DDD[2]), is.na(x$Latitude_DMM[3]))
x <- read_fixture("currencies.jmp")$data
same(x$AUD,c(1,2,2)); same(x$COP,c(3.14,2.78,1.41))
x <- read_fixture("rowstate.jmp")
stopifnot(x$columns$rowstate3$row_states$marker[2] == "\u25b2",
          x$columns$rowstate3$row_states$marker[3] == "\ua66e",
          x$columns$rowstate2$row_states$color[3] == "#C0C0C0",
          is.raw(x$columns$rowstate2$raw_row_states), which(x$rows$selected) == 3L)
x <- read_fixture("compact.jmp")$data
same(x$normalsubtype,c("aa","b","ccc","dd","dd"))
same(x$compactsubtype,c("aa","b","ccc","dd","dd"))
same(x$longcompact,c(strrep("x",254),strrep("y",255),"",strrep("z",256),strrep("z",256)))
for (entry in list(c("compact_UInt8.jmp",130),c("compact_UInt16.jmp",32770),c("compact_UInt32.jmp",65537))) {
  x <- read_fixture(entry[1])$data
  stopifnot(nrow(x) == as.numeric(entry[2]), ncol(x) == 1, tail(x$A,1) == paste0("a",entry[2]))
}
same(read_fixture("minusfour.jmp")$data[[1]], c("a","b","c"))
x <- read_fixture("bugMWE4.jmp")$data
same(x$c[1:3],c("cat","cat","dolor sit amet"))
same(x$d[1:3],c("bat","bat","consectetur adipiscing elit"))
same(x$e[1:3],c("bird","bird","sed do eiusmod"))
same(x$f[16:18],c("foo","bar","hello world"))

# Numeric limits that cannot be represented as R's native integer type.
same(internal(".jmp_numbers")(as.raw(c(0,0,0,128)),4,1), -2147483648)
stopifnot(!is.na(internal(".jmp_numbers")(as.raw(c(0,0,0,128)),4,1)))
same(internal(".jmp_uint")(as.raw(rep(255,8)),8,TRUE), -1)
same(internal(".jmp_i64_decimal")(as.raw(c(rep(255,7),127,rep(0,7),128,rep(255,8)))),
     c("9223372036854775807","-9223372036854775808","-1"))

# Lossless value-label dictionaries (stored codes remain separate).
uint32 <- function(n) writeBin(as.integer(n), raw(), size=4, endian="little")
null_text <- function(s) unlist(lapply(s,function(z)c(charToRaw(z),as.raw(0))),use.names=FALSE)
label_bytes <- null_text(c("Good","Bad"))
p <- c(uint32(2),uint32(16),writeBin(c(0,1),raw(),size=8,endian="little"),
       uint32(2),uint32(length(label_bytes)),label_bytes)
vl <- internal(".jmp_value_labels")(p,TRUE)
same(vl$values,c(0,1)); same(vl$labels,c("Good","Bad"))
expect_error_class(internal(".jmp_value_labels")(head(p,-1),TRUE),"jmp_corrupt_error")
key_bytes <- null_text(c("f","m")); label_bytes <- null_text(c("Fri","Mon"))
p <- c(uint32(2),uint32(length(key_bytes)),key_bytes,uint32(2),uint32(length(label_bytes)),label_bytes)
vl <- internal(".jmp_value_labels")(p,FALSE)
same(vl$values,c("f","m")); same(vl$labels,c("Fri","Mon"))

# Resource limits and malformed data are errors, never fabricated NA columns.
single <- readBin(file.path(fixture_dir,"singlecolumnsinglerow.jmp"),"raw",10000)
expect_error_class(internal(".read_jmp_binary")(raw(100)), "jmp_corrupt_error")
expect_error_class(internal(".read_jmp_binary")(head(single,30)), "jmp_corrupt_error")
negative_rows <- single
dimension_start <- internal(".jmp_find")(single,as.raw(c(7,0,8,0,0,0))) - 32
negative_rows[dimension_start + 1:8] <- as.raw(255)
expect_error_class(internal(".read_jmp_binary")(negative_rows), "jmp_limit_error")
expect_error_class(read_jmp(file.path(fixture_dir,"example1.jmp"),max_cells=2), "jmp_limit_error")
expect_error_class(internal(".jmp_utf8")(as.raw(c(255,254))), "jmp_encoding_error")
expect_error_class(internal(".jmp_gunzip")(raw(),1025,1024), "jmp_limit_error")
expect_error_class(internal(".jmp_gunzip")(charToRaw("abcdef"),6,1024), "jmp_corrupt_error")
compressed <- readBin(file.path(fixture_dir,"compressed.jmp"),"raw",10000)
h <- internal(".jmp_header")(compressed,1e7)
marker <- internal(".jmp_find")(compressed,as.raw(c(239,190,254,202)),h$offsets[1])
cursor <- internal(".jmp_cursor")(compressed,marker+4)
nzip <- cursor$num(8); nout <- cursor$num(8); zipped <- cursor$take(nzip)
expect_error_class(internal(".jmp_gunzip")(zipped,nout-1,1e8), "jmp_corrupt_error")
expect_error_class(internal(".jmp_gunzip")(zipped,nout+1,1e8), "jmp_corrupt_error")
budget <- new.env(parent=emptyenv()); budget$remaining <- 0
expect_error_class(internal(".jmp_read_column")(compressed,h,1,1e7,budget), "jmp_limit_error")

cat("Binary reader: all fixture, precision, metadata and corruption tests passed.\n")
