# Ticket 03 evidence

## RED

Command:

```text
zsh tests/ccp-free-wrapper.test.zsh
```

Result: exit 1 before `ccp-free` existed. The raw output is in `03-ccp-free-route-red.txt`. The four route groups reached the wrapper seam and failed as expected; the real FCC service was not touched.

## GREEN

Focused command:

```text
zsh tests/ccp-free-wrapper.test.zsh
```

Result: exit 0. The test covers token preflight, server already ready, cold kickstart, readiness timeout, launch failure, diagnostics, no-`claude` failure paths, process-local environment, exact model pinning, CLI model precedence, and the additive `ccp-list` entry.

Full bridge suite command:

```text
for test in tests/*.zsh; do zsh "$test"; done
```

Observed result: `bridge_tests=6/6`.

## Launchd

- Source: `fcc-free-setup/launchd/com.gggodlin.ccp-free-fcc.plist`
- Installed target: `~/Library/LaunchAgents/com.gggodlin.ccp-free-fcc.plist`
- `plutil -lint`: source and target both passed.
- Source and target are byte-identical.
- `launchctl print`: registered, `state = not running`, `runs = 0`, `last exit code = (never exited)`.
- Port probe: `127.0.0.1:18082` remained free.
- Plist contains no `RunAtLoad`, `KeepAlive`, `8317`, CLIProxyAPI paths, or existing service labels.

## Isolation

- `ccp-gpt` function hash matched the pre-change baseline.
- `ccp-relay` function hash matched the pre-change baseline.
- Changed-file secret-pattern scan completed without a match. No credential value is recorded in this evidence.
- No commit was created.

## Ticket 03 correction — macOS launchd/TCC

- First attempt: **FAIL**. The registered job started once and exited `126` because the launchd program and working directory were backed by the Desktop path; the dedicated error log reported the `getcwd` and `start-server` Operation not permitted failures.
- Focused artifact regression: **RED** against the old source plist, then **GREEN** after the correction. It rejects Desktop-backed `ProgramArguments` or `WorkingDirectory`, a missing runtime launcher, a launcher with mode other than `700`, and a launcher that is not byte-identical to tracked `bin/start-server`; it also passed against the tracked and actual artifacts.
- Runtime correction: the tracked launcher is installed with an atomic temporary-file replacement at `/Users/linhancheng/.local/share/ccp-free/bin/start-server`; its parent directory and file use mode `700`, and metadata records `runtime_launcher`. The existing runtime was repaired with only this copy action; the full installer was not rerun.
- Source and actual launchd target both linted successfully and remained byte-identical. The actual job was booted out, copied from the updated source, and bootstrapped again.
- Runtime-path integration: the job was registered and initially not running with port `18082` free; `launchctl kickstart` reached `GET /health` status `200`. Live `program` and `working directory` values both used the non-Desktop runtime path.
- Lifecycle stop: sending `SIGTERM` to the dedicated job left it registered and not running, kept port `18082` free, and showed no short-window automatic restart.
- No model prompt was sent.

## Final-review correction — 2026-08-23

- F1 RED: `python3 tests/test_install_launchd_job.py` failed before the helper existed. GREEN: the same focused suite passed with fake `HOME`, fake `LaunchAgents`, fake `launchctl`, and fake `plutil`; it covered mode `700`, atomic source-identical plist installation, correct `gui/$UID` bootstrap, registration verification, idempotent rerun, and refusal to overwrite an unknown existing target. The provision-order seam also passed: runtime installation precedes launchd registration.
- F2 RED: the added wrapper identity cases failed against the port-only implementation. GREEN: `zsh tests/ccp-free-wrapper.test.zsh` passed after checking dedicated-job state/PID and the `lsof` listener owner before reading the proxy token or invoking `claude`; the fake launchctl log now appends so `print` cannot erase kickstart evidence.
- F3 RED: the pure exact-model regression initially failed because the selection helper and expected-model constant were absent. GREEN: `python3 tests/test_fcc_endpoint_model.py` passed; selection now requires exact `provider_model_ref == FCC_EXPECTED_MODEL` (defaulting to the approved model) and passes only that entry's model id to the prompt path.
- Deterministic verification: setup tests `3/3`; bridge tests `6/6`; Python and zsh syntax checks, tracked plist lint, and both repository `git diff --check` checks passed.
- Actual dedicated-job correction: the helper booted out and re-bootstrapped only `com.gggodlin.ccp-free-fcc`; actual plist/source and runtime/source were byte-identical, runtime mode was `700`, the job was registered/not running, and port `18082` was free. A no-prompt `/health` probe returned `200`; launchd PID and the `lsof` listener PID matched. A fake-claude wrapper probe passed the production identity check without sending a model prompt; SIGTERM left the job registered/not running with no short-window auto-restart.
- Credential-shaped pattern scans over both final patches returned zero hits. No secret source was read and no credential value was recorded. Final live exact-model prompt acceptance remains for the acceptance worker.
- No commit was created.
