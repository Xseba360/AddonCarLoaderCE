![Add-on Car Loader CE](docs/media/logo.svg)

Adds vehicles to GTA IV Complete Edition 1.2.0.59 as new models, through the Fusion OverLoader (`update` folder).

Why downgrade the game to play it your way? Ever found a car mod with add-on audio while running the
latest version with FusionFix? There you go.

**[Download the latest release](https://github.com/Xseba360/AddonCarLoaderCE/releases/latest)**: unzip, run `addon_car_manager.exe`.

- **Add-on Car Loader CE** (`AddonCarLoaderCE.asi`): loads `addoncars.ide` after the vanilla IDEs
  (last model slots, saves stay valid), per-car FLA-format audio INIs, and `addoncars.fxt` names.
- **Add-on Car Manager CE** (`manager/`): Flutter app. Installs cars from mod archives, edits
  traffic groups, names, plates and scanner sounds. Backs up before every write. [Features](docs/FEATURES.md).

Requires [FusionFix](https://fusionfix.io/iv). LibertyCityPlates optional.

## Build

    build.bat
    cd manager && flutter build windows --release

VS 2022 x86 tools, Flutter 3.50+. Build the plugin first; the manager bundles it.

## Test

    cd manager && flutter test

Runs on a mock game tree. Set `GTA4_ROOT` to also run the tests that read the game's own data files.

## License

GPL-3.0. See [THIRD_PARTY.md](docs/THIRD_PARTY.md).
