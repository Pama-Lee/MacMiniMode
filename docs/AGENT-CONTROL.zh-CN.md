# Agent 任务

[English](AGENT-CONTROL.md)

让 Codex、Claude Code 或其他 MCP 客户端在构建、测试等长任务期间保持 Mac 运行。先把 Mac mini 模式安装到 `/Applications`。MCP 需要 macOS 13 及以上。

## 安装插件

把插件 ZIP 解压到一个固定文件夹。插件内含 Apple 芯片和 Intel 通用的 MCP 程序。

Codex：在包含 `codex` 文件夹的目录运行：

```sh
codex plugin marketplace add ./codex
codex plugin add macminimode@macminimode-local
```

安装后重启 Codex，在聊天中选择 MacMiniMode。

Claude Code：在包含 `claude-code` 文件夹的目录运行：

```sh
claude plugin marketplace add ./claude-code
claude plugin install macminimode@macminimode-local
```

也可以用 `claude --plugin-dir ./claude-code` 只在当前会话加载。

## 任务怎么工作

任务默认使用「自动」，插着电时保持运行。如果需要用电池继续运行，可以明确要求「始终开启」。多个任务同时运行时，始终开启优先；最后一个任务结束后，切到「始终关闭」。

菜单里的「Agent 任务」显示任务名称、来源和开始时间。客户端退出或断开连接后，任务仍会保留，可以从这个菜单结束遗留任务。手动选择任何模式都会清除全部任务，并采用你选择的模式。「退出并恢复睡眠」也会清除任务。

低电量设置同样适用于 Agent 任务。触发保护后，始终开启的任务切到自动；充电后是否恢复，由恢复设置决定。

## 低电量设置

从菜单打开「设置…」，开启低电量切换，在 10%–50% 之间选择触发电量，默认是 20%。使用电池且处于「始终开启」时，电量降到这个值就会切到「自动」。

可以选择「保持自动」或「恢复此前的始终开启」。选择恢复时，接入电源或电量达到触发值加 5% 后恢复。手动切换模式或修改设置会取消待恢复操作。

这项设置默认关闭。关闭时保留原有保护：10% 放行睡眠，15% 或接电后恢复。设置由后台服务保存。

## 其他 MCP 客户端

也可以直接在客户端的 MCP 配置中添加服务：

```json
{
  "mcpServers": {
    "macminimode": {
      "command": "/Applications/MacMiniMode.app/Contents/MacOS/macminimode-mcp",
      "args": []
    }
  }
}
```

| 工具 | 用途 |
| --- | --- |
| `get_status` | 查看模式、防睡眠状态、电源、电量、任务及低电量设置。 |
| `begin_task` | 登记任务，传入唯一 `id`、简短名称 `name`、来源 `source`，可选模式 `mode` 为 `auto` 或 `on`。 |
| `end_task` | 结束指定 `id` 的任务，支持重复调用。 |
| `set_mode` | 清除任务，切换到 `auto`、`on` 或 `off`。 |

重试请求时使用原来的任务 ID。返回值中的 `saved` 表示已保存，`applied` 表示系统已应用。电池供电时，自动模式即使返回 `applied: true` 也会允许睡眠。任务时间使用 ISO 8601 UTC 格式。

## 命令行

```sh
macminimode status --json
macminimode task begin UUID "Build project" "Script" auto
macminimode task end UUID
```

把 `UUID` 替换为新的任务标识。原有 `macminimode auto|on|off` 命令与菜单选择模式的效果相同。

## 移除插件

```sh
codex plugin remove macminimode@macminimode-local
# 或
claude plugin uninstall macminimode@macminimode-local
```

如有遗留任务，从菜单里的「Agent 任务」结束。

## 从源码构建

```sh
bash scripts/build.sh
bash scripts/package-plugins.sh
```

安装包和插件 ZIP 会写入 `build/`。MCP 使用官方 Swift SDK，依赖版本保存在 `MCP/Package.resolved`。

运行测试：

```sh
bash scripts/test-control.sh
bash scripts/test-quit.sh
swift test --package-path MCP
swift build --package-path MCP -c release --force-resolved-versions
python3 Tests/mcp_integration.py
```

集成测试使用临时后台服务和模拟电源数据。
