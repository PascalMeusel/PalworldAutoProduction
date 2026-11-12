# Steam Workshop packaging

The existing item is [AutoProduction: Bases](https://steamcommunity.com/sharedfiles/filedetails/?id=3837541491). Beta.2 was exercised with the official loader on Windows Steam Palworld `v1.0.5.102999`, using `UE4SSExperimentalPW` build `2281fa31`. Local packaging does not publish an update. See [test results and limits](testing.md).

Pocketpair's official loader supports [Lua (UE4SS) mods](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/01-General.md). A Lua package uses an `Info.json` and `Scripts` directory; its install rule places files under `Mods/NativeMods/UE4SS/Mods/{PackageName}`. See the official [package format](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/02-Package.md) and [installation rules](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/04-Tech.md).

## Build the package

```powershell
python tools/package.py
python tools/package_workshop.py
```

This creates `releases/PalworldAutoProduction-Workshop.zip` with root-level `Info.json`, scripts, enabled marker, README, MIT license and an example-data thumbnail. It contains neither UE4SS nor private settings. The metadata declares the `UE4SSExperimentalPW` package dependency described by the [UE4SS Workshop author](https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587). Other loader/game combinations remain unverified; the metadata does not enforce a minimum game revision.

## Updating and preserving settings

In a live beta.1 → beta.2 update, the official loader preserved `Scripts/automations.tsv` and `Scripts/priorities.tsv` byte for byte. The new mod then restored the saved recipe and ON state. These generated files are absent from the package's install manifest. Keep them and their `.bak` recovery copies when moving or reinstalling the mod.

Packaged files, including `Scripts/config.lua`, are replaced on update. Back up and reapply custom global configuration after a Workshop update. Per-station settings are in the preserved automation file. The manual `Install.ps1` additionally preserves `config.lua`.

## Test and upload

1. Start Steam using an account that owns Palworld, then open [Pocketpair's Mod Uploader](https://github.com/pocketpairjp/PalworldModUploader/releases).
2. Select the Palworld Workshop content directory and the existing item. For a new project only, create a **Lua** mod; Shift-click creates a local test package. Steam may require the account owner to accept its Workshop agreement.
3. Extract the archive into the package directory. Preserve the uploader's `.workshop.json`. Reload it in the uploader and verify the metadata and dependency.
4. Test with one active UE4SS installation and one copy of this mod. A manual loader and the Workshop loader must not be loaded together. Keep the manual setup and its user data backed up while testing on a separate save.
5. Check installation, enable/disable behavior, F8 navigation, production, saved ON/OFF choices, background forecasts and feed-box meals. Verify a version update preserves the generated settings, and document any changed loader behavior.
6. Bump `Version`, save metadata and use **Upload To Steam**. Check the required item, description, screenshots and visibility on the resulting Workshop page.

The [official uploader guide](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/03-ModUploader.md) describes the upload steps. Update the existing item rather than creating another one. Preserve `.workshop.json` and test settings migration/backups first. Building this package does not install, subscribe to, or upload anything.
