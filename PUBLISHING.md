# Maintaining the GitHub publication

Repository: https://github.com/eisuke-inoue386/jmp2r

## Before each update

1. Keep the upstream copyright/license notices in `inst/LICENSES/` and
   `inst/NOTICE`, including those covering the test fixtures.
2. Run package checks and update `VALIDATION.md` when verification changes.
   Describe supported formats and missing metadata accurately.
3. Commit only redistributable source and fixtures. Personal input files do
   not belong in this repository.

## Check and release

After editing `R/`, regenerate the standalone distribution and commit it:

```sh
Rscript tools/build-standalone.R
Rscript tools/build-standalone.R --check
Rscript --vanilla tools/check-standalone.R
```

Edit `R/` rather than `jmp2r.R`. The generated file includes license notices
and can be sourced without installing the package or downloading other files.
CI rejects an outdated generated file and checks standalone use on each OS.

The included workflow checks Windows, macOS and Linux on pushes and pull
requests. Confirm those jobs pass before tagging a release. Local validation
alone does not substitute for those platform checks.

```sh
R CMD build --no-build-vignettes .
R CMD check --no-manual jmp2r_0.2.0.tar.gz
```

For a release, tag the verified commit and create a GitHub Release. Attach a
freshly built R source package and, optionally, a tested Windows binary
package. `jmp2r-source.zip` is a source-folder archive, **not** an installable
R Windows binary package. Release assets must match the tagged source.

Direct `source()` use is documented in both READMEs. Use a commit SHA in place
of `main` when an exact, reproducible version is required.

## Future distribution

Add support using small, redistributable fixtures and exact expected values.
Record the producing JMP version when known. Keep unsupported input failures
and metadata limitations visible in the changelog. R-universe and CRAN have
not been configured or submitted. Before a CRAN submission, configure a
monitored maintainer email address in `DESCRIPTION`; a GitHub noreply address
does not provide a support mailbox. Use GitHub Issues for this publication.
