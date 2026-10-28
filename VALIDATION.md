# Validation record

Initial validation: 2026-10-21 (Asia/Tokyo).
Publication check: 2026-10-28 (Asia/Tokyo).

## Executed locally

- Windows 11 x64, R 4.6.1, UTF-8 locale.
- `R CMD build --no-build-vignettes`: passed.
- `R CMD check --no-manual`: **Status: OK**.
- Six test scripts cover the API, binary values, JRP, row/column metadata,
  default import conversions and plain-data output.
- The Windows binary ZIP installed into a separate clean library, with MD5
  verification and public `.jmp`/`.jrp`/analysis-conversion smoke tests passing.
- No third-party R package or JMP installation was used.

The check attempted to access package repository indexes, which this execution
environment could not reach. The dependency check still passed because the
package uses only R and its standard `utils` package. No tests were skipped
because of this. PDF reference-manual generation was not tested (`--no-manual`).

## Binary fixtures

All **19** `.jmp` fixtures from the MIT-licensed upstream suite were read, with
known expected values checked. These include:

- Numeric/integer missing-value sentinels and signed integer limits.
- Fixed/variable/compact strings, including 8/16/32-bit compact indices.
- 65,537 rows in the largest compact-string fixture.
- Compressed 10,000-row numeric/string/date/duration data.
- Japanese, accented text, symbols and emoji.
- Long column names, one-row/one-column files, dates/times, currencies,
  geographic values, and marker/color row-state columns.
- Synthetic internal tests for exact 64-bit decimal conversion and value-label
  payloads; these are not a claim of full-file 64-bit/value-label coverage for
  all possible JMP layouts.

Tests compare actual cells and metadata, not just whether a file opens. Expected
contents come from the upstream test suite; JMP itself was not used as a live
comparison engine in this environment.

## JRP and integrity checks

- Literal embedded data, UTF-8, modeling types, labels, order, missing codes,
  inert formulas, properties, empty tables, and serialization.
- External references, nested external calls, dynamic expressions, report
  commands, trailing commands, formula-only columns, inconsistent lengths,
  duplicate declarations, invalid UTF-8, truncated input and excessive nesting
  must fail.
- `Open(...)` in a quoted value or comment remains ordinary data.
- Wrong magic, truncated binary data, negative/oversized dimensions, invalid
  gzip headers, inconsistent decompressed lengths, and decompression budgets
  are tested.
- Requested analysis conversions fail when their metadata is unknown. Source
  values are unchanged after missing-code/factor conversion.

An independent review found and verified fixes for signed 64-bit length
rounding, accidental acceptance of non-gzip data, and metadata default/duplicate
handling. Additional adversarial/boundary checks were run outside the package
tests; the essential regression cases are included in the test suite.

## 0.2.0 row and column metadata (2026-10-28)

- All 19 public fixtures have a recognized table-property directory. The
  decoded selection flags do not cause rows to be removed.
- Synthetic edits to public fixtures verify default exclusion, explicit opt-out,
  hidden/selected-only rows, all rows excluded, unsupported row-state layouts,
  original row IDs, and alignment of temporal/row-state column metadata.
- A complete synthetic binary-column test covers ordinal modeling type and
  a literal numeric missing-code declaration; literal parser tests cover
  character codes, explicit ordering, truncation and rejected dynamic content.
- One local JMP Pro 19.1.1 table was checked against owner-confirmed exclusion,
  nominal/ordinal scales and a missing-code setting. The supplied table is not
  included in this repository or uploaded to GitHub. Public regression tests
  use the MIT fixtures and synthetic values only.
- In 0.2.0, unspecified ordinal order stopped conversion. See the 0.3.0
  behavior below; the original source order remains unchanged in metadata.

## 0.3.0 default import conversion (2026-10-28)

- Missing codes become NA before nominal/ordinal factor conversion by default.
- Synthetic tests cover numeric sorting, character sorting under the R locale,
  explicit source order, appearance/strict options, value labels, duplicate
  labels, empty columns, all-missing columns, opt-outs and repeated conversion.
- Original values/codes are preserved separately from display labels; inferred
  R order is diagnosed separately from the declared JMP order.
- The local owner-supplied table was rechecked for nominal factors, an ordered
  factor using R sorting, and conversion of the declared missing code to NA.
  The file remains local and is not part of the public test suite.

## 0.4.0 plain-data output (2026-10-28)

- Default output is a native data frame; tests cover direct column access,
  dimensions, factors, missing values, ordinary R summaries and serialization.
- Data columns named `data`, `source` and `diagnostics` are ordinary columns;
  import notes are stored separately as an attribute, without naming collisions.
- Plain-data output retains only import diagnostics, not source bytes or
  detailed metadata. Irrelevant unsupported-feature notes are omitted, while
  inferred ordinal order remains visible and can trigger metadata='error'.
- Existing decoder/conversion suites exercise `output = "dataset"` explicitly
  to verify the earlier detailed interface as well.

## Remaining limitations

- macOS and Linux execution: the GitHub workflow is configured. See the
  repository's Actions page for results after publication.
- A compatibility matrix of files generated by different JMP versions.
- Broader production-file coverage, non-UTF-8 binary data, all column properties,
  and ordinary JRP reports with analysis statements.
- Unrecognized binary row-state layouts, complex missing-code/value-order
  expressions, units, formulas, table scripts and other column properties.

This is an experimental reader, not a guarantee of lossless semantic migration.
