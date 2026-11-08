#!/bin/bash
#
# build.sh — 把 PixelCrop 编译并打包成可双击运行的 .app bundle
#
# 用法：
#   cd /path/to/PixelCrop
#   ./build.sh            # Debug 构建
#   ./build.sh release    # Release 构建（推荐，体积更小、运行更快）
#
# 产物：
#   build/PixelCrop.app
#
# 要求：
#   - macOS 26+ (Tahoe)
#   - Apple Silicon
#   - Xcode 26+ 命令行工具 (`xcode-select --install`)
#

set -euo pipefail

CONFIG="debug"
if [[ "${1:-}" == "release" ]]; then
    CONFIG="release"
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/PixelCrop.app"

echo "==> 配置：$CONFIG"
echo "==> 项目根目录：$ROOT"

# —— 1. 用 Swift Package Manager 编译 ——
echo "==> 编译 PixelCrop…"
if [[ "$CONFIG" == "release" ]]; then
    swift build -c release
    BIN="$ROOT/.build/release/PixelCrop"
else
    swift build
    BIN="$ROOT/.build/debug/PixelCrop"
fi

if [[ ! -f "$BIN" ]]; then
    echo "❌ 编译失败：找不到 $BIN"
    exit 1
fi

# —— 2. 组装 .app bundle ——
echo "==> 打包 .app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/PixelCrop"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# 简单的图标占位（系统照片图标），用户可自行替换。
# 真正的 .icns 需要在 Xcode 资产目录里制作，这里跳过。

# —— 3. 设置可执行权限 ——
chmod +x "$APP_DIR/Contents/MacOS/PixelCrop"

# —— 4. Gatekeeper：本地使用，移除 quarantine 属性 ——
xattr -cr "$APP_DIR" 2>/dev/null || true

echo "✅ 完成：$APP_DIR"
echo ""
echo "运行："
echo "  open '$APP_DIR'"
echo ""
echo "可选：拖到 /Applications："
echo "  mv '$APP_DIR' /Applications/"
