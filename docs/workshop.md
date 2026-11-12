# Steam Workshop packaging

**Status: beta.1 uploaded by the author; beta.2 is an untested native candidate.** The existing item is [AutoProduction: Bases](https://steamcommunity.com/sharedfiles/filedetails/?id=3837541491). Local packaging does not publish an update. Validate the candidate through the Workshop loader before uploading.

Pocketpair's official loader supports [Lua (UE4SS) mods](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/01-General.md). A Lua package uses an `Info.json` and `Scripts` directory; its install rule places files under `Mods/NativeMods/UE4SS/Mods/{PackageName}`. See the official [package format](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/02-Package.md) and [installation rules](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/04-Tech.md).

## Build the draft

```powershell
python tools/package.py
python tools/package_workshop.py
```

This creates `releases/PalworldAutoProduction-Workshop-draft.zip` with root-level `Info.json`, scripts, enabled marker, README, MIT license and an example-data thumbnail. It contains neither UE4SS nor private settings. The metadata declares the `UE4SSExperimentalPW` package dependency described by the [UE4SS Workshop author](https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587). Confirm the installed dependency's current package name and API compatibility during testing. Minimum game revision is deliberately unspecified until a supported Workshop combination is verified.

## Test and upload

1. Start Steam using an account that owns Palworld, then open [Pocketpair's Mod Uploader](https://github.com/pocketpairjp/PalworldModUploader/releases).
2. Select the Palworld Workshop content directory and create a **Lua** mod. Shift-click creates only a local test package; normal creation registers a Workshop item. Steam may require the account owner to accept its Workshop agreement.
3. Extract the draft archive into the generated package directory. Preserve the uploader's `.workshop.json`. Reload it in the uploader and verify the metadata and dependency. Use a private test item first.
4. Test with one active UE4SS installation and one copy of this mod. A manual loader and the Workshop loader must not be loaded together. Keep the manual setup and its user data backed up while testing on a separate save.
5. Check installation, enable/disable behavior, F8 navigation, production, saved ON/OFF choices, background forecasts and feed-box meals. Test a version update explicitly: `Scripts/config.lua`, `priorities.tsv*` and `automations.tsv*` must survive or be migrated to a persistent location. The manual installer preserves them, but that does not establish what the Workshop loader will do.
6. Set the minimum supported revision from the verified game build, bump `Version`, save metadata and use **Upload To Steam**. Set the required item, public description, screenshots and visibility on the resulting Workshop page.

The [official uploader guide](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/03-ModUploader.md) describes the upload steps. Update the existing item rather than creating another one. Preserve `.workshop.json` and test settings migration/backups first. Building this package does not install, subscribe to, or upload anything.
