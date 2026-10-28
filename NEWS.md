# jmp2r 0.4.1

- Inferred ordinal category order is retained in diagnostics but no longer
  emits a warning in the default mode. Other warnings remain enabled.
- Explicit strict modes (`metadata = "error"`, `ordinal_order = "error"`)
  keep their existing behavior.

# jmp2r 0.4.0

- Readers return a standard data frame by default. Use the returned object
  directly with `names`, `nrow`, `View`, formulas and other R functions.
- Use `output = "dataset"` for the earlier detailed list and `$data` interface.
- Plain-data output omits original bytes and detailed column/table/script
  metadata. It suppresses notes about unused unsupported features, while
  retaining conversion/representation diagnostics via `jmp_metadata(x)`.
- Exclusion, NA conversion and nominal/ordinal factor defaults are unchanged.

# jmp2r 0.3.0

- Readers default to missing-code conversion to NA, nominal factors and ordinal
  ordered factors. Opt out with `missing_codes = FALSE` and/or `factors = FALSE`.
- Explicit JMP category order takes precedence. Otherwise ordinal levels use
  R's standard sorted order, with inferred ordering recorded in diagnostics.
  `ordinal_order = "error"` or `"appearance"` selects alternative behavior.
- Preserve pre-conversion values and effective R levels alongside source
  definitions. Repeated conversion does not reinterpret labels as codes.
- Required unknown metadata stops the requested conversion, even in quiet mode.

# jmp2r 0.2.0

- Readers now default to `exclude_rows = TRUE`. Supported JMP table exclusion
  flags remove only excluded rows; set FALSE to retain all rows. Unknown
  exclusion metadata stops the default read instead of silently keeping rows.
- Preserve original row IDs, removal indices, source/returned row counts and
  alignment of per-row column metadata. Source files are never modified.
- Decode supported binary modeling-type attributes and literal missing-code
  and value-order properties without executing JSL. Ordinal category order
  is never inferred when unspecified.
- Keep the standalone `jmp2r.R` distribution synchronized with these changes.

# jmp2r 0.1.0

- Initial pure-R, JMP-independent reader for supported binary data tables.
- Preserve original source bytes, known storage/format/value-label metadata,
  and available undecoded column property payloads.
- Report unavailable semantic metadata instead of implying it was absent.
- Add a non-evaluating reader for a restricted single-table JRP literal grammar.
- Reject external references, dynamic JSL, and unsupported report statements.
- Provide explicit analysis conversion with metadata availability checks.
- Add base-R regression tests and a three-platform GitHub Actions workflow.
