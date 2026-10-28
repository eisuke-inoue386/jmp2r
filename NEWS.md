# jmp2r 0.1.0

- Initial pure-R, JMP-independent reader for supported binary data tables.
- Preserve original source bytes, known storage/format/value-label metadata,
  and available undecoded column property payloads.
- Report unavailable semantic metadata instead of implying it was absent.
- Add a non-evaluating reader for a restricted single-table JRP literal grammar.
- Reject external references, dynamic JSL, and unsupported report statements.
- Provide explicit analysis conversion with metadata availability checks.
- Add base-R regression tests and a three-platform GitHub Actions workflow.
