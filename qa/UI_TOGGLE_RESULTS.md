# 界面总开关验证（2026-10-23）

按键盘左上角、Esc 下方的【·／`】精简界面，再按一次恢复。精简时保留 Esc、基础操作提示及抓握时的蓄力/重心条。源码和 `build/MountainMark.pck` 均已更新。

## 范围

- 主 HUD、按钮、读线辅助线、岩点提示圈与动态高亮、支撑脚光环统一隐藏。
- 抓握准备期间独立保留拖拽力度槽、身体状态、悬挂倒计时、淡方向引导、回拉线、原始点和辅助后的实际落点。当前会帮助修正常见小误差并自动找稳，主提示简化为“绿色时松手”；详见[拖拽辅助验证](DRAG_ASSIST_RESULTS.md)。精简与完整界面使用同一组件，无重复绘制，切换不重置手势；松手、取消、暂停或手册打开时不残留。
- 独立提示层保留选脚、移重心、鼠标抓握、观察与读线、镁粉、返回、Esc 暂停及【·】恢复。提示随暂停、手册、日志、跌落与菜单状态切换，不拦截鼠标、不接收焦点；完整 HUD 恢复后不会重复显示。
- 菜单、日志、手册、暂停、跌落与登顶界面使用同一开关。隐藏按钮不能响应鼠标或 Tab；切换前按钮有焦点时按键仍有效。
- 物理键位优先，中英文布局一致；无物理键码时接受逻辑键码及 `·`、反引号、波浪号字符。忽略松键、自动重复和 Ctrl/Alt/Meta 组合，Shift 加同一物理键可用。
- 隐藏期间保留当前抓握、移动、重心、握力、镜头和声音状态，Esc 暂停及 Enter 跌落重试仍有效。切换路线后保持隐藏，恢复使用当前岩点反馈。
- 本次运行内保持选择，重启默认显示。两份玩家存档均未改变。

## 自动验证

| 检查 | 结果 |
| --- | --- |
| `ui_toggle_test.gd` 源工程 | 133 项通过，0 失败 |
| `ui_toggle_test.gd` 新 PCK（外部脚本） | 133 项通过，0 失败 |
| `package_reach_smoke.gd` 新 PCK | 14 项通过，0 失败 |
| `build/MountainMark.exe --smoke-test` | 退出码 0，存档 SHA-256 不变 |
| `git diff --check`（文本文件） | 通过 |

UI 测试通过真实 SubViewport 输入分发触发全局按键；覆盖所有模式、焦点、隐藏点击、按钮重建、隐藏中完成一次真实拖拽抓点、移动中切换、暂停/重试和世界重建。额外验证精简时操作提示与拖拽组件实际可见，恢复完整界面使用同一组件，释放/取消/暂停/手册切换无残留。打开手册取消当前拖拽，关闭后松开旧鼠标输入不会出手。测试使用隔离数据目录及 `--qa-capture`。PCK 通过项目自带 Godot 导出后再测，启动器加载该游戏包。

复现命令（项目根目录，测试运行器位于本地忽略目录）：

```powershell
.\.runtime\run-reach-check.ps1 -TestScript res://qa/ui_toggle_test.gd -CheckName ui-toggle
.\.runtime\run-reach-check.ps1 -TestScript E:/MountainMark/qa/ui_toggle_test.gd -CheckName ui-toggle-package -Pack E:/MountainMark/build/MountainMark.pck
.\.runtime\run-reach-check.ps1 -TestScript E:/MountainMark/qa/package_reach_smoke.gd -CheckName ui-package-smoke -Pack E:/MountainMark/build/MountainMark.pck
```

## 实际画面

`ui_toggle_preview.gd` 使用真实 GPU 在 1280 × 900 下截图，固定人物与镜头并暂停动画时间。精简后主 HUD、按钮及辅助圈隐藏，场景、实际岩点、底部操作提示及抓握准备中的蓄力/重心面板保留；玩法、菜单与手册的按键提示均清晰且无溢出。

- [界面显示](ui-toggle-visible.png) / [界面隐藏](ui-toggle-hidden.png) / [恢复显示](ui-toggle-restored.png)
- [菜单提示](ui-toggle-menu.png) / [隐藏菜单](ui-toggle-menu-hidden.png)
- [手册提示](ui-toggle-help.png) / [隐藏手册](ui-toggle-help-hidden.png)
- [预计命中](ui-toggle-drag-hit.png) / [回拉过短](ui-toggle-drag-short.png) / [方向偏离](ui-toggle-drag-angle.png)
- [辅助抓稳](ui-toggle-drag-assisted.png) / [明显偏差](ui-toggle-drag-miss.png) / [身体未稳时不显示就绪绿色](ui-toggle-drag-body-finding.png)

恢复后 1,152,000 像素中仅 8 像素存在最大 1/255 的通道误差，同状态连续帧基线为 6 像素、最大 1/255。恢复检查采用少于 100 像素且单通道误差不超过 1 的容差，结果通过；人物和镜头变换保持一致。拖拽长度与角度变化时，原始点、实际修正点与力度随之更新；目标容差圈由真实岩壁平面投影。只有满足全部出手条件时，实际预测圈、轨迹和主提示才显示就绪绿色。面板与底部操作栏相隔 52 像素，无重叠。

运行环境输出已有的根证书读取诊断，未出现脚本错误；离线功能、导出和启动检查均通过。
