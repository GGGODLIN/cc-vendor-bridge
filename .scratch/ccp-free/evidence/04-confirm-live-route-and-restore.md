# Ticket 04 — Live route confirmation and restore rehearsal

- Date: 2026-08-23
- Overall gate: **PASS** after the Ticket 03 runtime-path correction.
- Historical note: the first pre-correction `ccp-free --print` attempt exited non-zero with empty output; that failure remains documented below and is not overwritten.
- Vendor wrapper commit: `38fa1cf238666fe86164f2cae2ce636d134fed36`
- FCC source commit: `f405a929f7c14b168554528c54ffec46bf303faf`
- Provider: `nvidia_nim`
- Model: `nvidia_nim/nvidia/nemotron-3-super-120b-a12b`

## Expected versus actual

| Check | Expected | Actual | Verdict |
| --- | --- | --- | --- |
| Cold start and first real prompt | `ccp-free` starts the registered job, returns exit 0, and emits a non-empty response containing the marker | Corrected fresh-zsh invocation ran `ccp-free --print`; exit `0`, response non-empty `yes`, marker `match`, response bytes `10`; launchd runs increased `1→2` and port 18082 opened | PASS |
| NVIDIA route evidence | Successful HTTP request with provider `nvidia_nim` and the approved model, with no Anthropic, CLIProxyAPI, or fallback route | Authenticated FCC metadata returned HTTP `200`, 102 catalog rows, and 1 exact `provider_model_ref` match for `nvidia_nim/nvidia/nemotron-3-super-120b-a12b`. Server logs had 8 HTTP-200 classifications, 0 CLIProxyAPI/8317/public-Anthropic/fallback classifications, and no HTTP-500 | PASS |
| Launch failure and restart boundary | Unexpected exit leaves the job registered and stopped; a later wrapper call starts it again | Dedicated-label SIGKILL returned exit `0`; PID `82670`, runs `2→2`, and after 3 seconds the job was registered/not-running with port 18082 free. `auto_restart=no`; the next wrapper call subsequently started the job again | PASS |
| Second wrapper cold start and prompt | After the SIGKILL, only another wrapper call starts the job and returns a non-empty real response | Before call: job not-running and port free. Corrected fresh-zsh `ccp-free --print` returned exit `0`, response non-empty `yes`, marker `match`, response bytes `10`; launchd runs increased `2→3` and port opened | PASS |
| Final SIGTERM cleanup | The dedicated job remains registered/not-running and port 18082 is free | Dedicated-label SIGTERM returned exit `0`; after 3 seconds runs stayed `3`, state was `not running`, and port 18082 was free | PASS |
| Existing stack isolation | CLIProxyAPI identity, PID, port, and existing wrapper functions remain unchanged | Before and after: service path `/Users/linhancheng/Library/LaunchAgents/com.philip.cli-proxy-api.plist`, program `/Users/linhancheng/.cli-proxy-api/bin/cli-proxy-api`, PID `2415`, port 8317 open. `ccp-gpt` hash `9e9e080404f976b84ddf8ca91beea63329f7706f50cceccb62724a31beead41b`; `ccp-relay` hash `49a4ed9590cf3eb18b082cf034cb42b26b9f9538fad32f749260e2c6eb2a7f5b` | PASS |
| Regression suite | All six related zsh tests exit 0 | Six tests exit 0: `ccp-free-wrapper` 40 pass, `ccp-gpt-routing-fast` 10 pass, `ccp-gpt-whoami` 5/5 synthetic cases exit 0, `ccp-relay-priority` 7 pass, `cliproxy-codex-account-routing` 2 pass, `cliproxy-gpt-fast-config` 3 pass; total explicit pass lines 62, failures 0 | PASS |
| Plist and diff checks | Source and target plist are valid and identical; relevant git diff checks are clean | Both `plutil -lint` checks returned `OK`; source/target `cmp` was identical; wrapper and source plist `git diff --check` passed | PASS |
| Secret boundary | Canonical NVIDIA key and generated proxy token do not occur in trial artifacts, tracked working trees, diffs, outputs, or logs | Final exact-match scan covered 15,384 files and 2 repo diff blobs. NVIDIA key hits `0`; proxy-token hits `0`; diff hits for both `0`; verdict `PASS` | PASS |
| Restore rehearsal | Dry-run covers only the dedicated job, actual plist, FCC runtime/config, and named trial commits | `bash /Users/linhancheng/Desktop/projects/.claude/trials/ccp-free-fcc-v3/restore.sh` exited 0 and printed 7 plan lines. It names only `com.gggodlin.ccp-free-fcc`, FCC paths (runtime cleanup includes the runtime launcher), `cc-vendor-bridge` commits `f89e635` then `38fa1cf`, and `fcc-free-setup` commits `3881d9c` then `c2c4ca5` then `1f9ab55` then `29991bd`; forbidden existing-stack targets counted 0. No restore action executed | PASS |

## Historical first-attempt failure evidence

The registered target was initially `not running`, `runs=0`, and port 18082 was free. The first invocation used a fresh zsh process and sourced `/Users/linhancheng/Desktop/projects/cc-vendor-bridge/shell/ccp-functions.sh`; it did not call `start-server` directly. Launchd changed to `runs=1`, then reported `last exit code=126` and `not running`.

The dedicated error log classified the failure as:

- `shell-init: error retrieving current directory: getcwd: cannot access parent directories: Operation not permitted`
- `bash: /Users/linhancheng/Desktop/projects/fcc-free-setup/bin/start-server: Operation not permitted`

This was a macOS launchd/TCC access failure for the pre-correction Desktop-backed program path. The corrected Ticket 03 runtime launcher moved the live program and working directory under `/Users/linhancheng/.local/share/ccp-free`; the live checks below were then rerun from a fresh before snapshot.

## Commands and observations

- Corrected before snapshot: dedicated job registered/not-running with port 18082 free; CLIProxyAPI service identity, PID `2415`, and port 8317 captured; `ccp-gpt` and `ccp-relay` function hashes captured; repo HEAD/status captured.
- Historical first probe is retained above and was not counted as the corrected run.
- First corrected live probe: fresh zsh source followed by `ccp-free --print` with marker `FCC-T04-A`; only exit/non-empty/marker/byte-count fields were retained; response text was not recorded.
- Authenticated metadata probe: `GET /v1/models?view=messages` returned status `200`, 102 rows, and one exact approved NVIDIA provider/model match; response body and authorization value were not recorded.
- SIGKILL probe targeted only `gui/$UID/com.gggodlin.ccp-free-fcc`; after a 3-second wait runs stayed `2`, state was `not running`, and port 18082 was free.
- Second corrected live probe: fresh zsh source followed by marker `FCC-T04-B`; exit `0`, non-empty, marker match, and runs increased `2→3`; response text was not recorded.
- Final SIGTERM targeted only the dedicated label; after a 3-second wait the job remained registered/not-running, runs stayed `3`, and port 18082 was free.
- Existing-stack after snapshot: CLIProxyAPI remained PID `2415` on port 8317 and both wrapper hashes matched the before snapshot.
- Regression command ran all six files under `cc-vendor-bridge/tests/` listed in the ticket.
- Plist checks covered `/Users/linhancheng/Desktop/projects/fcc-free-setup/launchd/com.gggodlin.ccp-free-fcc.plist` and `/Users/linhancheng/Library/LaunchAgents/com.gggodlin.ccp-free-fcc.plist`.

## Restore plan

`/Users/linhancheng/Desktop/projects/.claude/trials/ccp-free-fcc-v3/restore.sh` is intentionally dry-run-only. It prints manual actions for:

1. Booting out only `gui/$UID/com.gggodlin.ccp-free-fcc`.
2. Removing the installed dedicated plist.
3. Removing `~/.config/ccp-free/proxy-token` and `~/.config/ccp-free`.
4. Removing `~/.local/share/ccp-free`.
5. Reverting `f89e635` then `38fa1cf` in `/Users/linhancheng/Desktop/projects/cc-vendor-bridge`.
6. Reverting `3881d9c` then `c2c4ca5` then `1f9ab55` then `29991bd` in `/Users/linhancheng/Desktop/projects/fcc-free-setup`; the runtime cleanup already includes the runtime launcher.

The script does not execute automatic git revert or runtime removal. Its `--execute` argument is rejected to prevent an unreviewed destructive operation.

## Known limitations

- The historical launchd/TCC failure was resolved by Ticket 03 commit `c2c4ca5`, which moved the program and working directory under the runtime data path; no code change was made in Ticket 04.
- The live lifecycle was verified only with the dedicated job label and a 3-second observation window; longer-term launchd behavior remains outside this ticket.
- `requirements-runtime.txt` uses lower bounds rather than a fully hash-locked dependency set.
- The FCC source archive is pinned by commit and SHA-256, but the runtime reuses the already-installed source/venv when present.
- The exact secret scan excludes the canonical CLIProxyAPI config, proxy-token file, and FCC managed `.env` as legal secret sources; all other scoped files and repo diffs had zero exact hits.

## Final state

- FCC launchd label remains registered and `not running`; runs is `3`, the runtime program is under `/Users/linhancheng/.local/share/ccp-free`, and port 18082 is free.
- CLIProxyAPI remains running with the same service identity, PID `2415`, and port 8317 open.
- No paid prompt was sent through `ccp-gpt` or `ccp-relay`.
- No credential value, generated token value, request header, or response body was written to this evidence.

## Ticket 03 correction after the initial RED

- The first real cold-start attempt remains **FAIL**: launchd used the Desktop-backed program and working-directory paths, recorded exit `126`, and never reached the FCC server.
- Ticket 03 artifact correction reached **GREEN**: the focused regression rejected the old Desktop plist and invalid runtime-launcher states, then passed for the tracked plist and actual runtime launcher after the minimal runtime copy.
- The updated source plist and actual target both passed `plutil -lint` and `cmp`; the actual job was booted out and bootstrapped from the updated source.
- Runtime-path health probe: the dedicated job began registered and not running with port `18082` free; `launchctl kickstart` reached `GET /health` status `200`. Live `program` and `working directory` values were both under `/Users/linhancheng/.local/share/ccp-free` and did not use Desktop.
- The dedicated-job `SIGTERM` lifecycle check left the job registered and not running, port `18082` free, and showed no short-window automatic restart.
- At the time of this correction note, Ticket 04 checks were not yet run; the corrected live confirmation in this evidence supersedes that interim state and records the completed PASS results.

## Final-review correction — 2026-08-23

- F1 added a tracked `bin/install-launchd-job.py` installer. The focused fake-home suite passed for source-identical atomic installation, fail-closed unknown-target handling, idempotence, launchd bootstrap, and registration verification; `provision-and-probe` runs it immediately after runtime installation.
- F2 added launchd state/PID plus `lsof` listener-owner authentication to `ccp-free`. The focused wrapper suite passed the not-running and rogue-listener cases without invoking the fake `claude` client, so the proxy token was not delivered on either failure path.
- F3 changed the HTTP smoke catalog selection from first `nvidia_nim/*` to exact approved `provider_model_ref` matching. The pure regression passed for both missing-exact rejection and exact-entry selection.
- Post-fix actual state: the dedicated label is registered/not running, the installed plist and runtime launcher match their tracked sources, the runtime launcher is mode `700`, and port `18082` is free. A real `/health` probe returned `200`; launchd PID and `lsof` listener PID matched. The wrapper identity path was exercised with `/usr/bin/true` as the claude seam, so no model prompt was sent; SIGTERM cleanup left the label stopped with no short-window auto-restart.
- This worker did not rerun the live exact-model prompt acceptance; the final acceptance worker must do that separately. No commit was created.

## Final acceptance rerun — 2026-08-23

- Final commits under test: cc-vendor `f89e635f9ce5dc9606a0d42b22db1b8e597f5cf4`; setup `3881d9c39c304b2bab79dfdfb9bf12867bad8065`, `c2c4ca5523c7402cae69bbc2512860af9068e08c`, `1f9ab559de5e4a0a11efabc3996432d1552d5bb7`, and `29991bd63ee954bce56d8238d8b2ff789dbaa809`.
- Corrected real cold start: fresh zsh wrapper call with marker `FCC-FINAL-A` returned exit `0`, response non-empty `yes`, marker `match`, response bytes `12`.
- Listener ownership: launchd PID `19362` and `/usr/sbin/lsof` port-18082 owner `19362` matched exactly.
- Approved route metadata: authenticated catalog HTTP `200`, 102 rows, exactly one approved `provider_model_ref` match for `nvidia_nim/nvidia/nemotron-3-super-120b-a12b`; no response body or authorization value was recorded.
- Final dedicated SIGTERM: authoritative `launchctl print` showed top-level `not running`, no PID, runs `3`, and port 18082 free. The job remained registered. A transient parser probe read a nested launchd `active` field during shutdown; the subsequent raw top-level state was the acceptance source of truth.
- Port-squatting negative control: real temporary localhost listener PID `40537` owned port 18082; the wrapper returned exit `1`, emitted the listener-owner identity diagnostic, did not call the temporary fake Claude executable, recorded `0` received bytes, and left port 18082 free. The fixture used only a temporary non-secret token file; the canonical token was not read by this control.
- Fresh registration control: tracked `bin/install-launchd-job.py` returned `launchd_job=registered`; actual job print showed the runtime program and working directory under `/Users/linhancheng/.local/share/ccp-free`, state `not running`, source/target plist identity matched, `provision-and-probe` called the helper exactly once, and README contained one provision flow.
- Deterministic setup tests: `test_install_launchd_job.py`, `test_launchd_artifacts.py`, and `test_fcc_endpoint_model.py` each exited `0` with a PASS marker. The exact-model regression rejected the alternate reference and selected the approved exact entry.
- Bridge regressions: all 6 zsh tests exited `0`; `ccp-free-wrapper` reported 46 pass, `ccp-gpt-routing-fast` 10, `ccp-gpt-whoami` had 5/5 synthetic cases exit 0, `ccp-relay-priority` 7, `cliproxy-codex-account-routing` 2, and `cliproxy-gpt-fast-config` 3; failures were `0`.
- Final syntax, plist, source/target, and diff checks passed. Final exact secret scan covered 15,384 files plus 2 repo diff blobs; NVIDIA key and proxy-token hits were `0`, including diff hits.
- Final state after the fresh-registration control: dedicated job remains registered/not-running with `runs=0`, runtime program and working directory under `/Users/linhancheng/.local/share/ccp-free`, and port 18082 free; CLIProxyAPI PID `2415` and port 8317 are unchanged. Restore remained dry-run-only and named cc-vendor `f89e635` then `38fa1cf`, setup `3881d9c` then `c2c4ca5` then `1f9ab55` then `29991bd`.
- No code, ticket, spec, or shared Verification Log changes were made by this final acceptance worker; no commit was created.
