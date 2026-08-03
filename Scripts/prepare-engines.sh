#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
STOCKFISH_SOURCE_DIR="$PROJECT_DIR/ThirdParty/Stockfish/sf_18/src"
MOBILE_MODEL_DIR="$PROJECT_DIR/Resources/Engines/Mobile"
MAC_ENGINE_PATH="$PROJECT_DIR/Resources/Engines/stockfish"
EMBEDDED_FRAMEWORK_PATH="$PROJECT_DIR/Vendor/QipanStockfishBridge.xcframework"

BIG_MODEL_NAME="nn-c288c895ea92.nnue"
BIG_MODEL_SHA256="c288c895ea924429ea9092e3f36b2b3c1f00f2a3a4c759ff7e57e79e3b43e4a7"
SMALL_MODEL_NAME="nn-37f18f62d772.nnue"
SMALL_MODEL_SHA256="37f18f62d772f3107e1d6aaca3898c130c3c86f2ab63e6555fbbca20635a899d"
MODEL_BASE_URL="https://tests.stockfishchess.org/api/nn"

FORCE_REBUILD=false
TEMP_DOWNLOAD_PATH=""

cleanup() {
    if [[ -n "$TEMP_DOWNLOAD_PATH" && -e "$TEMP_DOWNLOAD_PATH" ]]; then
        rm -f "$TEMP_DOWNLOAD_PATH"
    fi
}

trap cleanup EXIT

if [[ "${1:-}" == "--force" ]]; then
    FORCE_REBUILD=true
elif [[ $# -gt 0 ]]; then
    echo "用法：$0 [--force]"
    exit 2
fi

require_command() {
    local command_name=$1
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "缺少必要工具：$command_name"
        exit 1
    fi
}

file_matches_sha256() {
    local file_path=$1
    local expected_sha256=$2
    [[ -f "$file_path" ]] || return 1
    [[ "$(shasum -a 256 "$file_path" | cut -d ' ' -f 1)" == "$expected_sha256" ]]
}

download_model() {
    local model_name=$1
    local expected_sha256=$2
    local destination_path="$MOBILE_MODEL_DIR/$model_name"

    if file_matches_sha256 "$destination_path" "$expected_sha256"; then
        echo "✓ 模型已就绪：$model_name"
        return
    fi

    mkdir -p "$MOBILE_MODEL_DIR"
    TEMP_DOWNLOAD_PATH=$(mktemp "${TMPDIR:-/tmp}/qipan-model.XXXXXX")

    echo "↓ 正在下载 Stockfish 官方模型：$model_name"
    curl \
        --fail \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --progress-bar \
        "$MODEL_BASE_URL/$model_name" \
        --output "$TEMP_DOWNLOAD_PATH"

    if ! file_matches_sha256 "$TEMP_DOWNLOAD_PATH" "$expected_sha256"; then
        echo "模型校验失败：$model_name"
        exit 1
    fi

    mv "$TEMP_DOWNLOAD_PATH" "$destination_path"
    TEMP_DOWNLOAD_PATH=""
    echo "✓ 模型校验通过：$model_name"
}

build_macos_engine() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "macOS 引擎只能在 Mac 上编译。"
        exit 1
    fi

    local host_architecture
    local stockfish_architecture
    local job_count

    host_architecture=$(uname -m)
    case "$host_architecture" in
        arm64)
            stockfish_architecture="apple-silicon"
            ;;
        x86_64)
            stockfish_architecture="x86-64"
            ;;
        *)
            echo "暂不支持当前 Mac 架构：$host_architecture"
            exit 1
            ;;
    esac

    if [[ "$FORCE_REBUILD" == false && -x "$MAC_ENGINE_PATH" ]]; then
        echo "✓ macOS Stockfish 已就绪"
        return
    fi

    echo "⚙︎ 正在为 macOS ($host_architecture) 编译 Stockfish 18"
    cp "$MOBILE_MODEL_DIR/$BIG_MODEL_NAME" "$STOCKFISH_SOURCE_DIR/$BIG_MODEL_NAME"
    cp "$MOBILE_MODEL_DIR/$SMALL_MODEL_NAME" "$STOCKFISH_SOURCE_DIR/$SMALL_MODEL_NAME"

    job_count=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
    make -C "$STOCKFISH_SOURCE_DIR" ARCH="$stockfish_architecture" COMP=clang objclean
    make -C "$STOCKFISH_SOURCE_DIR" -j "$job_count" ARCH="$stockfish_architecture" COMP=clang all

    mkdir -p "${MAC_ENGINE_PATH:h}"
    install -m 755 "$STOCKFISH_SOURCE_DIR/stockfish" "$MAC_ENGINE_PATH"
    echo "✓ macOS Stockfish 已生成：Resources/Engines/stockfish"
}

build_mobile_bridge() {
    if [[ "$FORCE_REBUILD" == false && -d "$EMBEDDED_FRAMEWORK_PATH" ]]; then
        echo "✓ iPhone/iPad XCFramework 已就绪"
        return
    fi

    echo "⚙︎ 正在构建 iPhone/iPad Stockfish XCFramework"
    "$SCRIPT_DIR/build-embedded-stockfish.sh"
    echo "✓ iPhone/iPad XCFramework 已生成"
}

require_command curl
require_command shasum
require_command make
require_command xcodebuild
require_command xcrun

echo "准备 QipanChess 的 Stockfish 18 资源"
download_model "$BIG_MODEL_NAME" "$BIG_MODEL_SHA256"
download_model "$SMALL_MODEL_NAME" "$SMALL_MODEL_SHA256"
build_macos_engine
build_mobile_bridge

echo ""
echo "全部准备完成。现在可以打开 QipanChess.xcodeproj，选择 Mac、iPhone 或 iPad 运行。"
