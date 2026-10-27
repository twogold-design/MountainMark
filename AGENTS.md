# Mountain Mark: complete web project

- Maintain only the web version in this directory. The user wants BOTH the editable Godot project and the complete browser release here.
- `project.godot`, `scripts/`, `scenes/`, `assets/`, `web_shell.html` and `export_presets.cfg` are authoritative source. `index.html` is the formal release entry; all `index.*` files are required release artifacts.
- Run root `build.ps1` to publish. It uses a fresh staging project under sibling `MountainMark_web_source/.runtime` so generated caches do not pollute the competition folder. Do not create an archive unless requested.
- Keep generated tools, tests, logs, browser profiles and downloads on M:. Never write generated files to C:.
- Preserve the selected character animation from commit `1835fd7f33936c38184cb526dea850101004c5d9` unless the user requests changes. Retain automatic hands and two game modes.
- The HTML entry should show only the game name, enter button and necessary load/error status. Keep implementation and submission instructions out of the player interface.
- Double-clicking `index.html` must run the complete game without a server. `build.ps1` regenerates `index.offline.data.js` from the exported engine, game pack and audio worklets. Hosted pages must not load this extra bundle. Keep the complete folder below 200 MB.
- Historical Git metadata, QA scripts and development caches remain under sibling `MountainMark_web_source`. Its old `project/` is no longer the authoritative source. Do not restore Windows builds.
