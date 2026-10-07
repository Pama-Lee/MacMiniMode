#!/bin/bash
# 构建通用二进制、应用包和安装包：build/MacMiniMode-<版本>.pkg
#
# 钥匙串里有 Developer ID 证书时自动签名；再设置 NOTARY_PROFILE 就会公证并装订票据。
#   APP_IDENTITY    "Developer ID Application: ..."（默认自动查找）
#   PKG_IDENTITY    "Developer ID Installer: ..."（默认自动查找）
#   NOTARY_PROFILE  xcrun notarytool store-credentials 时起的名字
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${VERSION:-$(cat VERSION)}
MIN_OS=13.0
BUILD=build
ROOT=$BUILD/root
APP=$ROOT/Applications/MacMiniMode.app
DAEMON=$ROOT/Library/PrivilegedHelperTools/macmini-moded
PKG=$BUILD/MacMiniMode-$VERSION.pkg

find_identity() {
    security find-identity -v | sed -n "s/.*\"\($1: .*\)\"/\1/p" | head -n 1
}
APP_IDENTITY=${APP_IDENTITY:-$(find_identity "Developer ID Application")}
PKG_IDENTITY=${PKG_IDENTITY:-$(find_identity "Developer ID Installer")}
NOTARY_PROFILE=${NOTARY_PROFILE:-}

compile() {
    local source=$1 output=$2 name
    name=$(basename "$output")
    for arch in arm64 x86_64; do
        swiftc -O -target "$arch-apple-macos$MIN_OS" "$source" -o "$BUILD/obj/$name-$arch"
    done
    lipo -create "$BUILD/obj/$name-arm64" "$BUILD/obj/$name-x86_64" -output "$output"
}

echo "==> 编译 $VERSION（arm64 + x86_64）"
rm -rf "$BUILD"
mkdir -p "$BUILD/obj" "$APP/Contents/MacOS" "$APP/Contents/Resources" \
    "$(dirname "$DAEMON")" "$ROOT/Library/LaunchDaemons" "$ROOT/Library/LaunchAgents"

compile Sources/daemon/main.swift "$DAEMON"
compile Sources/menubar/main.swift "$APP/Contents/MacOS/MacMiniMode"

sed "s/@VERSION@/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
install -m 755 scripts/uninstall.sh "$APP/Contents/Resources/"
install -m 644 Resources/com.macminimode.daemon.plist "$ROOT/Library/LaunchDaemons/"
install -m 644 Resources/com.macminimode.menubar.plist "$ROOT/Library/LaunchAgents/"

echo "==> 签名"
if [ -n "$APP_IDENTITY" ]; then
    echo "    $APP_IDENTITY"
    SIGN=(codesign --force --options runtime --timestamp --sign "$APP_IDENTITY")
else
    echo "    未找到 Developer ID Application 证书，使用 ad-hoc 签名"
    SIGN=(codesign --force --sign -)
fi
"${SIGN[@]}" --identifier com.macminimode.daemon "$DAEMON"
"${SIGN[@]}" "$APP"

echo "==> 打包"
# 不关掉 relocatable 的话，安装器会把应用装到它在磁盘上找到的同名副本那里。
pkgbuild --analyze --root "$ROOT" "$BUILD/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$BUILD/component.plist"
pkgbuild --root "$ROOT" \
    --component-plist "$BUILD/component.plist" \
    --scripts Installer/scripts \
    --identifier com.macminimode.pkg \
    --version "$VERSION" \
    --install-location / \
    --ownership recommended \
    "$BUILD/MacMiniMode-component.pkg" >/dev/null

sed "s/@VERSION@/$VERSION/g" Installer/distribution.xml > "$BUILD/distribution.xml"
PRODUCT=(productbuild --distribution "$BUILD/distribution.xml" --resources Installer/Resources --package-path "$BUILD")
if [ -n "$PKG_IDENTITY" ]; then
    echo "    $PKG_IDENTITY"
    PRODUCT+=(--sign "$PKG_IDENTITY" --timestamp)
else
    echo "    未找到 Developer ID Installer 证书，安装包未签名"
fi
"${PRODUCT[@]}" "$PKG" >/dev/null

if [ -n "$PKG_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "==> 公证"
    xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$PKG"
fi

echo "==> 完成：$PKG"
if [ -z "$PKG_IDENTITY" ]; then
    echo "    未签名：只适合本机测试，别人下载后会被 Gatekeeper 拦截"
elif [ -z "$NOTARY_PROFILE" ]; then
    echo "    已签名但未公证：设置 NOTARY_PROFILE 后重新构建"
else
    echo "    已签名并公证，可以直接分发"
fi
