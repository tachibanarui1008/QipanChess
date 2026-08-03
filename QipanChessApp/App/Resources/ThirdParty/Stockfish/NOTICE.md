# Stockfish 18

QipanChess 随 App 分发 Stockfish 18：macOS 使用 Apple Silicon / arm64 可执行文件；iOS/iPadOS 使用由 Stockfish 18 源码构建的静态库，以及两个 NNUE 网络文件。

- Project: Stockfish
- Website: https://stockfishchess.org/
- Source: https://github.com/official-stockfish/Stockfish
- Release tag: `sf_18`
- License: GNU General Public License version 3 (GPLv3)

本工程中用于生成移动端静态库的对应源码位于 `ThirdParty/Stockfish/sf_18/`，本项目的 C API 桥接代码位于 `ThirdParty/Stockfish/Bridge/`，可复现构建脚本位于 `Scripts/build-embedded-stockfish.sh`。

完整许可证文本见同目录的 `Copying.txt`，贡献者名单见 `AUTHORS.txt`。分发应用时，需要遵守 GPLv3，并向接收者提供与所分发二进制对应的完整源代码或符合许可证要求的源码书面要约。
