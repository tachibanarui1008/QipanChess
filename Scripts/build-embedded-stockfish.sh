#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
SOURCE_DIR="$PROJECT_DIR/ThirdParty/Stockfish/sf_18/src"
BRIDGE_DIR="$PROJECT_DIR/ThirdParty/Stockfish/Bridge"
BUILD_DIR="$PROJECT_DIR/.build/EmbeddedStockfish"
OUTPUT_PATH="$PROJECT_DIR/Vendor/QipanStockfishBridge.xcframework"

SOURCES=(
    "$SOURCE_DIR/benchmark.cpp"
    "$SOURCE_DIR/bitboard.cpp"
    "$SOURCE_DIR/engine.cpp"
    "$SOURCE_DIR/evaluate.cpp"
    "$SOURCE_DIR/memory.cpp"
    "$SOURCE_DIR/misc.cpp"
    "$SOURCE_DIR/movegen.cpp"
    "$SOURCE_DIR/movepick.cpp"
    "$SOURCE_DIR/position.cpp"
    "$SOURCE_DIR/score.cpp"
    "$SOURCE_DIR/search.cpp"
    "$SOURCE_DIR/thread.cpp"
    "$SOURCE_DIR/timeman.cpp"
    "$SOURCE_DIR/tt.cpp"
    "$SOURCE_DIR/tune.cpp"
    "$SOURCE_DIR/uci.cpp"
    "$SOURCE_DIR/ucioption.cpp"
    "$SOURCE_DIR/syzygy/tbprobe.cpp"
    "$SOURCE_DIR/nnue/network.cpp"
    "$SOURCE_DIR/nnue/nnue_accumulator.cpp"
    "$SOURCE_DIR/nnue/nnue_misc.cpp"
    "$SOURCE_DIR/nnue/features/full_threats.cpp"
    "$SOURCE_DIR/nnue/features/half_ka_v2_hm.cpp"
    "$BRIDGE_DIR/QipanStockfishBridge.cpp"
)

build_library() {
    local sdk=$1
    local target=$2
    local architecture=$3
    local output_dir=$4
    local sdk_path
    local compiler
    local architecture_flags=()

    sdk_path=$(xcrun --sdk "$sdk" --show-sdk-path)
    compiler=$(xcrun --sdk "$sdk" --find clang++)

    if [[ "$architecture" == "arm64" ]]; then
        architecture_flags=(-DUSE_NEON=8)
    else
        architecture_flags=(-DUSE_SSE2 -msse2)
    fi

    mkdir -p "$output_dir/objects"

    local object_files=()
    local index=0
    for source_file in "${SOURCES[@]}"; do
        local object_file="$output_dir/objects/$index.o"
        "$compiler" \
            -c "$source_file" \
            -o "$object_file" \
            -target "$target" \
            -isysroot "$sdk_path" \
            -std=c++17 \
            -stdlib=libc++ \
            -O3 \
            -DNDEBUG \
            -DIS_64BIT \
            -DNNUE_EMBEDDING_OFF \
            -DNO_PREFETCH \
            -fno-exceptions \
            -fvisibility=hidden \
            -I"$SOURCE_DIR" \
            -I"$BRIDGE_DIR/include" \
            "${architecture_flags[@]}"
        object_files+=("$object_file")
        index=$((index + 1))
    done

    xcrun libtool -static -o "$output_dir/libQipanStockfishBridge.a" "${object_files[@]}"
}

mkdir -p "$BUILD_DIR"

build_library iphoneos arm64-apple-ios17.0 arm64 "$BUILD_DIR/iphoneos-arm64"
build_library iphonesimulator arm64-apple-ios17.0-simulator arm64 "$BUILD_DIR/iphonesimulator-arm64"
build_library iphonesimulator x86_64-apple-ios17.0-simulator x86_64 "$BUILD_DIR/iphonesimulator-x86_64"

mkdir -p "$BUILD_DIR/iphonesimulator-universal"
xcrun lipo -create \
    "$BUILD_DIR/iphonesimulator-arm64/libQipanStockfishBridge.a" \
    "$BUILD_DIR/iphonesimulator-x86_64/libQipanStockfishBridge.a" \
    -output "$BUILD_DIR/iphonesimulator-universal/libQipanStockfishBridge.a"

if [[ -e "$OUTPUT_PATH" ]]; then
    rm -rf "$OUTPUT_PATH"
fi

xcodebuild -create-xcframework \
    -library "$BUILD_DIR/iphoneos-arm64/libQipanStockfishBridge.a" \
    -headers "$BRIDGE_DIR/include" \
    -library "$BUILD_DIR/iphonesimulator-universal/libQipanStockfishBridge.a" \
    -headers "$BRIDGE_DIR/include" \
    -output "$OUTPUT_PATH"
