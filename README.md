<p align="center">
  <img src="docs/icon.png" width="128" alt="Mac mini Mode icon">
</p>

<h1 align="center">Mac mini Mode</h1>

<p align="center">Keep a plugged-in MacBook running with the lid closed. Unplug it and it sleeps like a normal laptop again.</p>

<p align="center"><b>English</b> · <a href="README.zh-CN.md">简体中文</a></p>

Mac mini Mode turns a MacBook into an always-on home server or headless Mac. It gives you clamshell mode without an external display or a dummy HDMI plug, and there is no `caffeinate` or `sudo pmset disablesleep` to remember. Because it follows the power adapter, your MacBook never stays awake inside your bag.

## Features

- **On when plugged in**: sleep is disabled on AC power, so your Mac keeps running with the lid closed and no display attached.
- **Off when unplugged**: normal sleep returns on battery. If the lid is already closed, the Mac sleeps right away.
- **Menu bar control**: switch between Automatic, Always On and Always Off, and see the current state at a glance.

## Install

Download the latest `.pkg` from [Releases](../../releases/latest) and open it. It takes effect as soon as the installer finishes.

The installer is signed and notarized by Apple. Requires macOS 13 or later, on Apple silicon or Intel.

<p align="center">
  <img src="docs/installer-en.png" width="620" alt="Mac mini Mode installer">
</p>

## Uninstall

```bash
sudo /Applications/MacMiniMode.app/Contents/Resources/uninstall.sh
```

## License

[MIT](LICENSE)
