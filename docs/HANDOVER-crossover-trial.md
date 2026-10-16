# Handover: CrossOver trial support

For a Claude Code session continuing this work on a Mac with an active CrossOver trial.
Read the safety rules first, and follow them throughout.

## Safety rules (non-negotiable)

This Mac belongs to someone who agreed to let it be used for this. Her CrossOver install,
bottles, games and saves are not test data.

1. **Read-only investigation.** Never write, move, rename or delete anything that belongs to
   CrossOver. That covers `~/Library/Preferences/com.codeweavers.*`,
   `~/Library/Application Support/CrossOver`, its bottles, the keychain, and
   `/Applications/CrossOver.app`. Don't run `defaults write`/`delete`, `plutil -replace`, or
   `security` with `-d` or any delete/add verb, and don't use `sudo`.
2. **Only plainly readable data.** The trial reader may use information CrossOver keeps in an
   ordinary readable form, such as a plist value, a config line, or the output of a bundled
   tool. Do **not** decrypt, deobfuscate, disassemble or patch CrossOver, and don't read
   keychain secrets. If the trial state is only available that way, **stop and report it.**
   That is a finding, not a puzzle to solve. Don't fall back to anything that lets the user
   supply or extend an end date.
3. **Never reset, extend or hide the trial.** The feature exists to honour an active trial
   and to stop when it ends.
4. **No personal data in commits or reports.** Leave out names, emails, license keys and
   serials. `tools/crossover-trial-probe.sh` already redacts these from its output.
5. **Running the app changes Steam.** Installing NotProton modifies the Steam app and adds a
   compatibility tool under `~/Library/Application Support/Steam`. Get the owner's explicit
   OK before any integration test that installs it, and use NotProton's own backup and
   uninstall when finished.

## Where things are

- Repository: https://github.com/c7cj5z9kb6-arch/Ethical-Proton. This is an independent fork.
  Never open PRs against the original NotProton.
- Branch: `feature/crossover-trial-support`, 3 commits plus this document, on top of `main` at `e8d2ea8`.
- Clone it to a path **without spaces**, because the Makefile breaks on them:
  `git clone -b feature/crossover-trial-support https://github.com/c7cj5z9kb6-arch/Ethical-Proton.git ~/src/Ethical-Proton`

## What already exists

| Piece | File | What it does |
|---|---|---|
| Trial verdict | `app/Sources/NotProtonApp/Model/CrossOverLicense.swift` | `check()` verifies a paid license first. If none verifies, it asks `trialSource` for a `TrialReading` (`.notFound`, `.active(expires:)` or `.ended(expired:)`). An active trial ending after `now` returns `licensed: true` with `trialExpires` set. A trial at or past its end is refused, and `trialHasEnded` puts the right message in the dialogs. |
| **The missing piece** | same file, `defaultTrialSource` | Currently `{ _ in .notFound }`. **This is what to implement.** |
| Marker | `Model/TrialMarker.swift` | `RunnerSetup.prepare` writes `runners/crossover-<build>/notproton-trial` with the trial's end in epoch seconds. A paid license removes it, both on setup and on Status refresh. |
| Launch check | `dylib/feats/compat_run.sh`, `refuse_ended_trial` | Runs before Wine. It refuses to launch when the marker's time has passed or the marker can't be read. |
| UI | `Views/StatusView.swift`, `Model/CrossOverRow.swift` | Rows read "trial until <date>" or "trial ended". The dialogs name an ended trial. |
| Probe | `tools/crossover-trial-probe.sh` | Read-only, redacted report of what CrossOver exposes. |
| Tests | `CrossOverLicenseTests`, `TrialMarkerTests` (includes a Swift-to-run-script agreement test), `CrossOverRowTests`, `RunnerSwitchTests`, `dylib/tests/trialcheck.sh` | All pass. |

## Ground truth to validate against

On **2026-10-16**, CrossOver on this Mac said: *"This is a time limited trial version of
CrossOver. It will stop working in 10 days."* The reader's end date should therefore come out
around **2026-10-26**. Use this only to **check** the reader. Never hard-code it, and never
derive an end date from an assumed trial length.

## Outstanding tasks

1. **Investigate (read-only).** Run `sh tools/crossover-trial-probe.sh > /tmp/probe.txt` and read
   it. Then follow up with read-only commands as needed. Find where CrossOver records the trial
   and whether its end, or its start plus a length CrossOver itself states, is plainly readable.
   Write down the evidence, meaning the file or key and why it matches the "10 days" message,
   in this document under "Findings".
2. **Implement the reader** in `CrossOverLicense.swift`, or a new `Model/CrossOverTrial.swift`
   that `defaultTrialSource` calls:
   - pure read, no side effects;
   - `.notFound` when the data is absent;
   - `.ended(expired: nil)` when it is present but can't be parsed (fail closed);
   - never `.active` without a concrete end date read from CrossOver's data.
3. **Test it** with fixture files shaped like the real data, but with made-up values and no
   personal data. Cover: active, ended, absent, malformed, and paid license plus trial
   (paid wins).
4. **Verify on the real install:**
   - `CrossOverLicense.check` reports `licensed`, `isTrial`, and a `trialExpires` near 2026-10-26.
   - A dry check that installs nothing can use a small test or `swift run` snippet calling
     `check(crossOverRoot:)` on `/Applications/CrossOver.app/Contents/SharedSupport/CrossOver`.
   - The full app flow (setup, marker written, game launches) only with the owner's OK; see
     safety rule 5.
5. **Translations.** New user-facing strings need zh-Hans entries in
   `Resources/Localization/Localizable.xcstrings`, or `make l10ncheck` fails.
6. Commit to this branch, push, and open a PR **within the fork** (`main` ←
   `feature/crossover-trial-support`).

## Build and test

Requirements, matching `.github/workflows/app.yml`:
- Xcode 27.
- `brew install cmake mingw-w64 fontforge gpatch bison flex shellcheck`.
- Put Homebrew's bison and flex first on `PATH`. macOS's bison 2.3 is too old for Wine.

```sh
git clone --no-checkout https://github.com/jmpews/Dobby.git vendor/dobby
git -C vendor/dobby checkout 5dfc8546954ce3b3198132ab13fddb89ee92cdd7
python3 -m venv scratch/fontvenv && scratch/fontvenv/bin/pip install afdko==4.0.3 fonttools==4.66.1
export PATH="$PWD/scratch/fontvenv/bin:$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"
make dobby && make all && make overlay-shim && make iconmaker appinfo
make bridge && make fonts && make app-payload        # the Wine bridge build is the slow step
cd app && swift test --no-parallel && cd ..          # expect every test to pass (523 as of this handover)
make -s l10ncheck trialcheck buildcheck envcheck scriptcheck runcheck
make app && make -s mincheck                         # out/NotProton.app
```

For quick iteration without the payload, run `cd app && swift build --build-tests && swift test`.
In that mode about 30 payload-dependent tests fail on unmodified code too. That is expected.

## Findings

_(To be filled in by the investigating session: evidence, where the trial is recorded, and
the reader's design.)_
