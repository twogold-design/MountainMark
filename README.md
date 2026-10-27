# 山痕 · 完整网页版

本文件夹同时保留可直接发布的网页游戏与可编辑的 Godot 网页工程，以后只维护网页版。

- `index.html`：正式游戏入口，比赛平台通过它启动。
- `index.wasm`：浏览器版 Godot 引擎，无需 Windows 的 Godot.exe。
- `index.pck`：打包后的场景、角色、脚本、音效及其他游戏资源。
- `project.godot`：可编辑的 Godot 工程入口。
- `scripts/`、`scenes/`、`assets/`：完整网页版源码、场景和资源。
- `web_shell.html`：正式入口页的源模板；修改它并重新构建即可更新 index.html。
- `export_presets.cfg`：网页导出设置，已排除网页发布文件自身，避免重复打入游戏包。
- `build.ps1`：重新导出到当前目录。构建缓存放在同级 MountainMark_web_source/.runtime，不进入本文件夹。
- `index.offline.data.js`：供直接打开本地入口时加载的完整游戏资源；比赛平台通过 HTTP/HTTPS 启动时不会加载它。

## 试玩与编辑

双击 `index.html`，点击“进入游戏”即可游玩，无需启动脚本或本地服务器。建议使用电脑上的新版 Edge 或 Chrome。也支持比赛平台通过 HTTP/HTTPS 打开同一入口。

使用 D:\tools\Godot-4.7.2 中的 Godot 打开本目录 project.godot，即可修改完整的网页版工程。完成修改后运行 build.ps1 更新发布文件。当前支持电脑键鼠，角色动画沿用已选定的版本。

## 参加比赛

本目录保留完整网页版，可整体打包。压缩时选中文件夹内的内容，使小写 index.html 位于压缩包根目录。运行游戏必须同时保留全部 index.* 发布文件。源码和构建工具不参与网页启动，但可随完整工程保留。

若自行使用编辑器产生 .godot 或其他缓存，提交时可排除这些缓存。当前未生成压缩包。
