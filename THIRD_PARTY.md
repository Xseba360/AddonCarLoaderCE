# Third-party parts

The project's own code is under the GNU GPL v3 ([LICENSE](LICENSE)). It includes or ships these:

| Part | Where | License |
| ---- | ----- | ------- |
| fastman92 limit adjuster 7.6: vehicle audio structs, INI format, and the dump of the game's sound settings | `structs_from_fla.inc`, parts of `AddonCarLoader.cpp`, `manager/windows/sounds/` | MIT, [licenses/fastman92-limit-adjuster.txt](licenses/fastman92-limit-adjuster.txt) |
| 7-Zip (separate program, run to unpack `.7z` and `.rar`) | `manager/windows/7zip/` | LGPL 2.1 with unRAR restriction, `manager/windows/7zip/License.txt` |
| Switzer (font) | `manager/fonts/Switzer-Extrabold.ttf` | ITF Free Font License, `manager/fonts/Switzer-LICENSE.txt` |
| Alte DIN 1451 Mittelschrift (font) | `manager/fonts/din1451alt.ttf` | SIL Open Font License 1.1, `manager/fonts/din1451alt-OFL.txt` |
| Flutter, Forui and the other Dart packages | fetched by `flutter pub get` | BSD 3-Clause, MIT and others; the About tab lists each with its text |

The MIT and BSD parts are compatible with the GPL. 7-Zip and the fonts are separate works shipped
alongside the program, not linked into it.
