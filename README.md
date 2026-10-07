<p align="center">
  <img src="docs/icon.png" width="128" alt="Mac mini 模式">
</p>

<h1 align="center">Mac mini 模式</h1>

<p align="center">让插着电的 MacBook 合上盖子也能一直运行；拔掉电源，它又是一台正常睡眠的笔记本。</p>

把 MacBook 放在家里当服务器用，最麻烦的是合盖就睡。手动 `pmset disablesleep 1` 能解决，但哪天忘了改回来，合着盖子塞进包里，它会一路发热到没电。Mac mini 模式把这件事交给电源状态自动处理。

## 功能

- **插电自动开启**：接入电源后禁止睡眠，合盖、不接显示器也照常运行。
- **拔电自动关闭**：切到电池立即恢复正常睡眠；如果此时已经合盖，会直接让机器睡下去。
- **菜单栏状态**：Mac mini 图标表示模式开启，笔记本图标表示关闭。
- **手动三档**：自动、始终开启、始终关闭，选择在重启后依然保留。
- **不留尾巴**：服务停止或卸载时，睡眠设置会恢复原样。

## 安装

1. 到 [Releases](../../releases) 下载最新的 `MacMiniMode-x.y.z.pkg`。
2. 双击打开，按提示完成安装，过程需要管理员密码。
3. 装完即生效，菜单栏会出现图标，不需要重启。

<p align="center">
  <img src="docs/installer.png" width="620" alt="安装器界面">
</p>

支持 macOS 13 及以上，Apple 芯片和 Intel 都可以。

## 使用

点菜单栏图标可以看到当前模式、供电方式和电量，并切换三档：

| 模式 | 行为 |
| --- | --- |
| 自动 | 插电开启，拔电关闭（默认） |
| 始终开启 | 用电池也不睡眠，合盖放进包里会持续发热，用完记得切回自动 |
| 始终关闭 | 插着电也正常睡眠 |

长期插电使用时，建议到「系统设置 → 电池」把充电上限设为 80%。

## 工作原理

安装包会放两样东西：

- 后台服务 `/Library/PrivilegedHelperTools/macmini-moded`，以 root 身份运行。它监听系统的电源变化通知，在插电和拔电时执行 `pmset -a disablesleep 1` 或 `0`，并每分钟核对一次实际状态。
- 菜单栏应用 `/Applications/MacMiniMode.app`，以当前用户身份运行，只负责显示状态。切换模式时它给后台服务发一个 Darwin 通知，自己不需要任何权限。

日志在 `/var/log/macmini-mode.log`。

## 卸载

```bash
sudo /Applications/MacMiniMode.app/Contents/Resources/uninstall.sh
```

## 从源码构建

需要 Xcode 命令行工具。

```bash
./scripts/build.sh
```

产物在 `build/MacMiniMode-<版本>.pkg`。没有 Developer ID 证书时得到的是未签名安装包，适合本机自用。

### 发布签名版

分发给别人需要 Apple Developer Program 账号：

1. 在 Xcode → Settings → Accounts → Manage Certificates 里创建 **Developer ID Application** 和 **Developer ID Installer** 两张证书。
2. 保存公证凭据（会提示输入 App 专用密码）：
   ```bash
   xcrun notarytool store-credentials MacMiniMode --apple-id <Apple ID> --team-id <Team ID>
   ```
3. 构建、签名、公证一步完成：
   ```bash
   NOTARY_PROFILE=MacMiniMode ./scripts/build.sh
   ```

图标和安装器背景由 `swift scripts/make-assets.swift` 生成。

## 许可

[MIT](LICENSE)
