#!/bin/bash
# 验证退出等待、失败重试和断言检查，不修改系统电源设置。
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/macminimode-quit-tests.XXXXXX")
trap 'rm -rf "$TEST_BUILD"' EXIT
swiftc Sources/menubar/QuitController.swift Tests/QuitControllerTests.swift -o "$TEST_BUILD/test-quit"
"$TEST_BUILD/test-quit"
