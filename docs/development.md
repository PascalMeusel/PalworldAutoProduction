# Development

## Run checks

Use Python 3.10+ on Windows. The renderer uses the installed Segoe UI font.

```powershell
python -m pip install -r requirements-dev.txt
python tests/run.py
python tests/render_preview.py
python tools/package.py
python tools/package_workshop.py
```

The Lua suites use fresh Lua 5.4 runtimes through Lupa. They check forecast math, scoped station persistence and interrupted writes, host-only priority management, native menu ownership, widget lifetimes, production requests and confirmations, and AFK meal eligibility/transfers. The twenty-minute food-history case checks that background sampling keeps a forecast ready without reading Pal rosters or production queues. These native-shaped mocks do not substitute for testing inside Palworld.

`tests/preview.lua` supplies example data to the actual scene builder. Generated PNGs are layout illustrations, not evidence of a live session. The renderer rejects text overflow.

## Runtime structure

- `main.lua`: native lifecycle hooks, workstation controls and refill scheduling.
- `automation_state.lua` / `automation_store.lua`: live-object binding and durable data-only per-world station records.
- `base_data.lua`: owned-base discovery, incremental snapshots and lightweight current-base food readings.
- `telemetry.lua` / `forecast.lua` / `base_insights.lua`: bounded observations and derived statistics.
- `base_stats.lua` / `overview_scene.lua` / `overview_ui.lua`: dashboard state, declarative layout and native widget rendering/input.
- `priorities.lua` / `priority_policy.lua` / `priority_store.lua`: work permissions, scheduling and recovery.
- `auto_eat.lua`: idle eligibility, verified feed-box transfer and normal item consumption.

Keep reflected object access on the registered game-thread Lua state. Use the shared deferred callback helper; do not put native calls in Lua coroutines. Periodic collection advances a state machine and publishes completed snapshots. Never convert unknown game-owned FText using the affected UE4SS Lua bridge: native conversion can abort outside Lua's error handling. Read FString/FName values and use established label fallbacks.

The mod uses reflected API signatures, not hardcoded offsets. Reference signatures were checked against the [Palworld Modding Kit](https://github.com/localcc/PalworldModdingKit) and a [public SDK snapshot](https://github.com/goku19991998-cell/palworld-internal-dx11/tree/3e8ea6ba880713b0b9ae74f0426b1385b26cdd01/libs/SDKLibrary/SDK). Neither is bundled. UE4SS is a separate runtime dependency; Pal Work Priority is not required or bundled.

## Release and testing scope

The manual release and installer share `release-files.txt`. The builder checks its exact file set and verifies every ZIP entry against source. It excludes saved preferences, SDKs, binaries, game assets, logs and local tooling. The installer preserves user settings and backs up the existing installation. GitHub Actions runs the same checks on Windows.

Development testing used Windows Steam Palworld `v1.0.5.102999` and UE4SS Palworld fork commit `ba2efd55`. Earlier native tests exercised menu navigation, scrolling, production refills, ingredient planning, worker care and real feed-box meals on a separate test world. Newer game and Workshop loader builds are not implied compatible by those observations.

Before claiming a new build works in-game, exercise F8/Escape/tab switching, reload saved ON and OFF choices, change bases, leave Bases closed beyond ten minutes while moving normally, and test a hungry idle character with an empty food inventory. Confirm priority restoration before uninstalling. Report game version, UE4SS build, reproduction steps and relevant redacted log lines in an issue; omit saves and private identifiers.
