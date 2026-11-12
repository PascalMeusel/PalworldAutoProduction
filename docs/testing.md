# Beta.2 acceptance plan

Status: automated coverage and example layouts only. Native acceptance, performance comparison and publishing are deferred until the user makes the PC available. Do not substitute an old beta.1 live session for these checks.

## Report and investigation

The Workshop comment reports a crash while adjusting automatic production, and production stopping after ten crafts despite supplies. No player log, call stack, version or hosting details are available.

Ten is the default batch size. Confirmed code defects included permanently dropping the active automation after one unavailable recipe read, and allowing an unrelated menu/meal failure to abort the scan before production. Regression tests exercise recovery from both conditions. The old start path requested a full configured batch without explicitly adapting to the game's current craft limit. The candidate also removes a reused native UI model with forced loading flags, validates native recipe/quantity/binding, and avoids destroyed widget updates. Those are risk reductions, not an attribution of the player's native crash.

A focused replay against the published `main.lua` (matching the local Workshop source blob) produced these results:

| Injected condition after the first batch | Published beta.1 | Candidate |
| --- | --- | --- |
| Recipe list temporarily empty, then recovers | ON lost; no refill | ON retained; refills |
| Workstation control throws while the queue is empty | ON retained; no refill | Other jobs continue; refills |

## Automated checks

Run `python tests/run.py`, `python tests/render_preview.py`, `python tools/package.py`, and `python tools/package_workshop.py`.

Coverage includes twenty consecutive refills interleaved with ingredient inspections and simulated native collection; transient empty/failing recipes; partial/zero/unknown supply limits; wrong native model bindings and recipes; unrelated menu/meal/statistics failures; one failing station among healthy ones; pickup waits; a completed batch missed by polling; rejected-request backoff; 1,000 notifications coalesced without queue/food/UI work inside hooks; paused notification cancellation; shared stock reservations including unconfirmed requests; unknown inventory reads; old-file migration, corrupt/interrupted writes and per-world isolation. Nine example layouts are rendered and checked for text overflow. These mocks cannot reproduce a native crash or measure game FPS.

## Native acceptance on an isolated save

1. Back up the existing save and automation/priority settings. Use one active loader and one copy of the mod. Record game, loader and candidate versions. Keep real play data separate from the test world.
2. Open the kitchen, select Salad, enable Auto Produce and observe at least twenty refills. Alternate opening/closing the native station, Supplies, Batch settings and other menu tabs. Check ON remains green, native transport still works, and there are no new errors/crash reports.
3. Set batch sizes 1 and 10; verify actual accepted quantities and repeated refills. Change size while a batch is active; the current queue must not change. Reload the world and restart the process; verify recipe, ON/OFF, batch size and target survive. Also migrate a beta.1 settings file and test a failed write.
4. Let output accumulate by withholding transport. Verify Waiting for pickup and no replacement queue. Collect it manually, then with Pals. Confirm which native notifications fire on host and client. Test a one-craft batch that finishes and is collected between polls; it must not enter a false 25-second confirmation timeout.
5. Try zero ingredients, ingredients for fewer crafts than the batch setting, unavailable power and a locked recipe. Verify precise status, smaller batches, automatic recovery, and bounded retries. Leave/revisit the base and reload streamed objects without losing settings.
6. Set a stock target at one kitchen, then two kitchens producing the same item. Verify the shared budget includes queued, finished and unconfirmed automatic output. Test a multi-item recipe yield, removing stock, changing recipes, unknown inventory, manual queues and another player's activity. Confirm the game's base-item counting function excludes carried items and establish whether it already includes station output; conservative double-counting must resolve after transport. Do not advertise strict caps against manual/other-mod production.
7. Recheck F8/Escape/input restoration, Party tab navigation, long-list scrolling, food forecast continuity and priority restoration. Return to title and reopen a world repeatedly to exercise native destruction and object collection. Exit normally and check for a new crash report rather than relying on the sticky previous-session warning.

## Performance gate

Compare the same isolated save and camera position with `FAST_REFILL = false` and `true`, after warm-up. Observe frame times and script/native timings with no automations, one kitchen, and many enabled stations; repeat with stock targets off/on and the menu closed/open. Check event storms, at least ten minutes of normal play and memory growth across repeated batches. No faster global scanning, unbounded callback growth or material frame-time regression is acceptable. If the native hooks are noisy or unsafe on a supported loader, disable them for release and keep polling until corrected.

## Publication gate

Only after the native checks: verify migration through an actual Workshop update; preserve uploader identity and user data; rerun checks and reproducible packaging; update the candidate wording/version/testing scope; then push GitHub and upload to the existing Workshop item. Keep any unverified loader/client combinations explicitly unverified. No update has been published by preparing these files.

## Feature research

Players have asked for automatic refills and a “craft until stock reaches X” control in [this September 2026 discussion](https://www.reddit.com/r/Palworld/comments/1w6nsk3/palworld_has_automation_but_its_really_limited_or/), and station production limits alongside priorities in [this July 2026 discussion](https://www.reddit.com/r/Palworld/comments/1uybs83/palworld_needs_a_priority_system_for_jobs_and/). The candidate's optional stock target fills that gap in this mod. These reports establish player interest, not the absence of similar features in every other mod. Automatic healing, storage routing and recursive ingredient crafting remain outside this stability update because they require broader native behavior and separate validation.
