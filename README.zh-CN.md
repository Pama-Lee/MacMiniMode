<p align="center">
  <img src="docs/icon.png" width="128" alt="Mac mini 模式图标">
</p>

<h1 align="center">Mac mini 模式</h1>

<p align="center">让插着电的 MacBook 合上盖子也能一直运行；拔掉电源，它又是一台正常睡眠的笔记本。</p>

<p align="center">
  <a href="https://github.com/Pama-Lee/MacMiniMode/releases/latest/download/MacMiniMode.pkg"><img src="docs/download-zh.svg" height="48" alt="下载安装包"></a>
</p>

<p align="center"><a href="README.md">English</a> · <b>简体中文</b></p>

## 安装

1. 点上面的「下载安装包」，会得到一个 `MacMiniMode.pkg`。
2. 双击打开，一路点「继续」，中途输入一次开机密码。
3. 装完菜单栏会多出一个图标，这时已经在工作了，不用重启。

安装包已签名并通过 Apple 公证，打开时不会提示「无法验证开发者」。支持 macOS 12 及以上，Apple 芯片和 Intel 均可。

<p align="center">
  <img src="docs/installer-zh.png" width="620" alt="Mac mini 模式安装器">
</p>

## 它做什么

把 MacBook 放在家里当 Mac mini、家用服务器或无头主机用：合盖不休眠，不需要外接显示器或 HDMI 假负载，也不用记着敲 `caffeinate` 或 `sudo pmset disablesleep`。它跟随电源适配器自动开关，所以 MacBook 不会在包里一直醒着。

- **插电自动开启**：接入电源后不再睡眠，合盖、不接显示器也照常运行。
- **拔电自动关闭**：切到电池立即恢复正常睡眠；已合盖则直接入睡。
- **菜单栏切换**：自动、始终开启、始终关闭三档，当前状态一眼可见。
- **体检**：一键检查远程登录、屏幕共享、电池和电源设置是否就绪，并可复制诊断信息用于反馈。
- **低电量保护**：「始终开启」时用电池，电量降到 10% 会自动放行睡眠，不会硬撑到断电。
- **命令行**：`macminimode status`、`macminimode on|off|auto`，也可以在快捷指令里用「运行 Shell 脚本」调用。

## 更新

应用每天会向 GitHub 查一次有没有新版本。有的话会自动下载、校验签名，然后弹窗问你要不要安装；点「安装」会打开系统安装器。不想自动检查，可以在菜单里取消勾选「自动检查更新」，需要时再点「检查更新…」。

## 遇到问题

先升级到最新版。如果合盖后还是会睡，点菜单栏图标里的「体检…」，再点「复制诊断信息」，把内容贴到 [Issues](../../issues)。常见原因是远程桌面或清理类软件会定时改电源设置，新版会自动改回去，并在日志里记一笔。

## 卸载

```bash
sudo /Applications/MacMiniMode.app/Contents/Resources/uninstall.sh
```

## 许可

[MIT](LICENSE)
