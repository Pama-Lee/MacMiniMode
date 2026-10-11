#!/bin/bash
# 注入合盖状态和锁屏接口，不锁住测试机器，不修改生产偏好或电源设置。
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/macminimode-lid-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
swiftc Sources/menubar/ScreenLock.swift Sources/menubar/LidMonitor.swift \
    Sources/menubar/LidLockController.swift Tests/LidLockTests.swift -o "$TEST_BUILD/test-lid-lock"
"$TEST_BUILD/test-lid-lock"
swiftc Sources/menubar/LidLockController.swift Sources/menubar/LidLockMenu.swift \
    Tests/LidLockMenuTests.swift -o "$TEST_BUILD/test-lid-menu"
"$TEST_BUILD/test-lid-menu"
