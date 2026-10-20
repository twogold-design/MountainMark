# 最终验证记录

- 引擎：用户指定的 Godot 4.7.2 stable，Windows / Compatibility 渲染。
- 独立入口：build/MountainMark.exe 已经通过启动检查；启动器正确加载内置 engine/Godot.exe 与 MountainMark.pck。
- 独立打包路线：71 个抓点、56 次落手、0 次保护，抵达末端检查点 70；qa/packaged-route.log 输出 QA_SUCCESS。
- 主场景集成：27/27；正常退出：7/7；详见 INTEGRATION_RESULTS.md。
- 实际图形渲染：01-title.png、02-climbing.png、03-midpoint.png、04-summit.png；经逐图检查修正颜色、圆环阴影、峰顶脚位与界面对比。
- 最终正常退出及独立路线完成退出无 ObjectDB / Resource 泄漏。
- 项目、打包、测试、存档、日志和显式临时目录均位于 M:/NewGames/MountainMark。
- 测试未创建玩家存档，也未改写用户已有存档。

环境附注：沙箱内 Godot 会打印一次 Windows 根证书库读取提示；本游戏完全离线，该提示不影响资源加载、渲染或攀登。
