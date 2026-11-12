# Changelog

## 0.1.0-beta.2 — Unreleased candidate

Native acceptance and performance testing are pending. This build has not been uploaded to Workshop or GitHub Releases.

- Preserve Auto Produce through temporary recipe/identity gaps; isolate menu, food, statistics and individual station failures.
- Use a fresh native production model per operation with normal engine lifetime flags; validate station binding, selected recipe and quantity before requesting work.
- Avoid updating destroyed workstation controls and report missing output, pickup waits, resources and power separately.
- Save a batch size per station, with presets and single-craft adjustments in Bases → Production → Batch. Use a smaller batch when ingredients cannot support the configured size.
- Coalesce finish/pickup notifications into bounded station-only checks, retaining polling and rejected-request backoff. Recognize a small batch that finishes before polling observes its queue.
- Optional base stock targets, including reservations for tracked automatic batches so multiple automated stations share the budget. Unlimited remains the default.
- Migrate version 1 automation settings without losing recipes or ON/OFF choices; retain interrupted-write recovery.
- Add production, notification-flood, shared-stock and settings regression coverage, an example settings layout, and a native testing checklist.

The Workshop report establishes a crash and a stop after ten crafts, but supplies no log, call stack, game/loader versions or host/client details. The corrected defects can interrupt refills under test; they do not establish the cause of that player's crash.

## 0.1.0-beta.1 — 2026-11-10

First public beta of the Windows Steam UE4SS mod.

- Bases tab integrated into Palworld's main menu, with F8/Escape navigation.
- Scrollable Pal and production lists, station names, locations and filters.
- Automatic workstation refills with green ON feedback and durable per-world station settings.
- Built-in work priorities, including restoration of original work permissions.
- Food stock, wellbeing and production statistics, history graphs, nutrition forecasts and ingredient planning.
- Background food tracking independent of the menu and AFK eating.
- Optional AFK meals using real food from the current guild base's feed boxes.
- Automated Lua regression tests, example layout rendering and reproducible release packaging.

Windows single-player and local-host behavior have been exercised during development. Dedicated-server administration and controller navigation inside the dashboard are not implemented. The latest persistence and background-food fixes have automated coverage; testing across game/loader versions and multiplayer configurations remains limited. Workshop packaging is a draft pending native install/update tests.
