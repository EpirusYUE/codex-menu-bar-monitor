# Codex Monitor

一个原生 macOS 菜单栏应用：

- 余量方框始终显示；Codex 有任务运行时，白色半透明光带沿方框外沿连续循环。
- 图标右上角用蓝色圆形徽标显示正在运行的任务数。
- 每个任务完成时，图标闪烁一次；同时完成多个任务会依次闪烁。
- 中断任务会立即停止计数，但不会触发“完成”闪烁。
- 空闲时显示剩余额度，例如 `84% 5h`；没有 5 小时窗口时显示周额度，例如 `75% w`。
- 点击图标可查看当前任务、打开 Codex、手动刷新或测试闪烁效果。

应用只读 `~/.codex/state_5.sqlite` 和对应的本地 rollout 记录，以
`task_started` / `task_complete` 事件判断状态。它不会修改 Codex 数据。

## 构建

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "outputs/Codex Monitor.app"
```

也可以在终端验证当前检测结果：

```bash
"outputs/Codex Monitor.app/Contents/MacOS/CodexMenuBar" --status
"outputs/Codex Monitor.app/Contents/MacOS/CodexMenuBar" --quota
```

要求 macOS 13 或更高版本，以及 Xcode Command Line Tools。
