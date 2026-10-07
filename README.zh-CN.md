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

安装包已签名并通过 Apple 公证，打开时不会提示「无法验证开发者」。支持 macOS 13 及以上，Apple 芯片和 Intel 均可。

<p align="center">
  <img src="docs/installer-zh.png" width="620" alt="Mac mini 模式安装器">
</p>

## 它做什么

把 MacBook 放在家里当 Mac mini、家用服务器或无头主机用：合盖不休眠，不需要外接显示器或 HDMI 假负载，也不用记着敲 `caffeinate` 或 `sudo pmset disablesleep`。它跟随电源适配器自动开关，所以 MacBook 不会在包里一直醒着。

- **插电自动开启**：接入电源后不再睡眠，合盖、不接显示器也照常运行。
- **拔电自动关闭**：切到电池立即恢复正常睡眠；已合盖则直接入睡。
- **菜单栏切换**：自动、始终开启、始终关闭三档，当前状态一眼可见。

## 卸载

```bash
sudo /Applications/MacMiniMode.app/Contents/Resources/uninstall.sh
```

## 许可

[MIT](LICENSE)
