# Contributing to CGNAT Inspector

Thanks for considering a contribution! This project aims to stay a
dependency-light, ShellCheck-clean, well-tested Bash CLI tool. Please keep
that spirit in mind when contributing.

## Getting started

```bash
git clone https://github.com/giftbalogun/cgnat-inspector.git
cd cgnat-inspector
./tests/run-tests.sh          # confirm the baseline passes
./cgnat-inspector --help      # sanity check
```

No build step is required -- it's plain Bash.

## Project structure

```text
cgnat-inspector      # main entrypoint; orchestration only, no business logic
install.sh           # installer
uninstall.sh         # uninstaller
lib/                 # all real logic lives here, one concern per file
tests/               # test-*.sh files + shared test-framework.sh + run-tests.sh
docs/                # user-facing documentation
.github/             # CI workflows, issue/PR templates
```

Keep `cgnat-inspector` itself as a thin orchestration layer. New detection
logic, formatting, or parsing belongs in the appropriate `lib/*.sh` file so
it can be unit tested in isolation.

## Code style

- **Bash, not `sh`.** Scripts use `#!/usr/bin/env bash` and bash-specific
  features (arrays, `[[ ]]`, etc.) are fine.
- **ShellCheck clean.** Run `shellcheck -x cgnat-inspector install.sh
  uninstall.sh lib/*.sh tests/*.sh` before opening a PR. If you must
  suppress a warning, add a `# shellcheck disable=SCxxxx` comment directly
  above the line with a short reason, not a blanket disable.
- **Guard against double-sourcing.** Every file in `lib/` starts with an
  `if [[ -n "${CGNAT_X_LOADED:-}" ]]; then return 0; fi` guard. Follow this
  pattern for new library files.
- **No I/O side effects in `lib/detect.sh`.** That file is pure logic
  (string/boolean in, string/boolean out) so it stays trivially testable.
  Network calls belong in `lib/network.sh`; presentation belongs in
  `lib/output.sh` or `lib/json.sh`.
- **Defensive by default.** Every function that can fail should return a
  non-zero exit code rather than printing a fabricated value. Callers
  should always check return codes, not just emptiness of output.
- **Log to stderr, results to stdout.** `log_*` functions in
  `lib/utils.sh` already do this -- keep it that way so `--json` output
  stays parseable even with `--verbose`/`--debug` enabled.

## Adding a new evidence signal

1. Add the raw data-gathering function to `lib/network.sh` or
   `lib/traceroute.sh` (whichever fits).
2. Add a `SCORE_*` weight constant to `lib/detect.sh` and fold it into
   `detect_compute_score`. Follow the existing pattern: a *known and
   true* signal scores its full weight; an *unknown* signal scores a
   smaller "uncertainty" weight (never the same as a confirmed positive
   -- that's the project's core false-positive guard). Document the
   weight in `docs/how-it-works.md`.
3. Add the corresponding line(s) to `detect_build_evidence`, using
   conditional inclusion (see existing examples) if the line only makes
   sense when certain other data is known.
4. Wire the raw fact and its classification into `cgnat-inspector`'s
   `main()` function.
5. `lib/json.sh`'s evidence/array helpers already consume
   `detect_build_evidence`'s output generically -- no JSON changes are
   usually needed unless you're adding an entirely new top-level field.
6. Add tests to `tests/test-private.sh` (scoring/status) and, if the
   signal comes from a new parsing routine, a dedicated test file (see
   `tests/test-stun.sh` for the pattern of testing wire-format parsing
   with hand-crafted fixtures, with no live network required).
7. Update `README.md`'s feature list and `CHANGELOG.md` under
   `[Unreleased]`.

## Adding a new CLI flag

1. Add the flag to `print_help()` and `parse_args()` in `cgnat-inspector`.
2. Wire the resulting `OPT_*` variable into `main()`.
3. Document it in `README.md` and `docs/api.md` if it affects JSON output.
4. Add a changelog entry.

## Testing

```bash
./tests/run-tests.sh                # run everything
bash tests/test-private.sh          # run a single suite
```

- `tests/test-ipcalc.sh` -- pure IP arithmetic (`ip_in_cidr`, `ip_to_int`, etc.)
- `tests/test-private.sh` -- address classification, the evidence-based scoring engine, status/exit-code logic
- `tests/test-json.sh` -- JSON escaping and report assembly (including the evidence array)
- `tests/test-network.sh` -- network functions; live-network checks are
  skipped gracefully (not failed) when the CI runner has no internet
  access, but local/offline-safe checks always run
- `tests/test-stun.sh` -- the pure-Bash STUN response parser, using
  hand-crafted byte fixtures (no live network required)

When adding a test, prefer `assert_true`/`assert_false`/`assert_equals`
from `tests/test-framework.sh` over hand-rolled `if` statements, and give
each assertion a clear, specific description (it doubles as the test
suite's documentation when it fails).

## Commit / PR process

1. Fork the repo and create a feature branch.
2. Make your changes, following the style guide above.
3. Run the full test suite and ShellCheck locally.
4. Update `CHANGELOG.md` under `[Unreleased]`.
5. Open a PR using the provided template -- fill out the checklist
   honestly, it's there to help reviewers, not to slow you down.

## Reporting bugs / requesting features

Please use the issue templates under `.github/ISSUE_TEMPLATE/` -- they ask
for the specific details (OS, dependencies present, exact command run)
that are almost always needed to reproduce a networking-related issue.

## Code of conduct

Be respectful, assume good faith, and keep discussion focused on the
technical merits of a change. This is a small utility project maintained
by volunteers in their spare time.
