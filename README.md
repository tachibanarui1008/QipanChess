# 棋盘分析（QipanChess）

一个原生 SwiftUI 多设备国际象棋分析原型，同一工程支持 macOS、iPhone 和 iPad。当前三个平台都已内置 Stockfish 18，可在每步棋后实时显示中立局势判断、当前走棋方的最佳着法、对手最佳应对和后续主变化。

## 运行环境

- macOS 14 或更高版本
- iOS / iPadOS 17 或更高版本
- Xcode 16 或更高版本
- macOS 引擎会由准备脚本针对当前 Apple 芯片或 Intel Mac 编译
- iOS/iPadOS 内嵌库支持 arm64 真机，以及 arm64/x86_64 模拟器

## 首次准备（一条命令）

由于 GitHub 普通仓库不接受超过 100 MiB 的单个文件，引擎成品和大型 NNUE 模型不直接存入 Git。克隆项目后，在项目目录运行：

```sh
./Scripts/prepare-engines.sh
```

脚本会自动完成：

- 从 Stockfish 官方服务器下载两个 NNUE 模型并校验 SHA-256
- 为当前 Mac 架构编译 Stockfish 18 可执行引擎
- 检查并在需要时重建 iPhone/iPad 使用的静态 XCFramework

准备成功后再打开 `QipanChess.xcodeproj`。需要强制重新编译全部引擎资源时运行 `./Scripts/prepare-engines.sh --force`。

## 在 Xcode 中运行

1. 双击打开 `QipanChess.xcodeproj`。
2. 在顶部 Scheme 中选择 `QipanChess`。
3. 选择运行设备：
   - macOS：`My Mac`
   - iPhone：任意 iPhone 模拟器
   - iPad：任意 iPad 模拟器
4. 点击 Run（▶）或按 `⌘R`。

真机运行时，需要在 QipanChess Target 的 Signing & Capabilities 中选择自己的开发团队；模拟器和 Mac 本机调试不需要额外配置。

## 引擎放在哪里

运行准备脚本后，Stockfish 会成为 App 的内置组件，不会安装到 `/usr/local`、`/Applications` 等系统目录，也不要求最终用户单独安装。

- macOS 工程内引擎：`Resources/Engines/stockfish`
- macOS 构建成品：`QipanChess.app/Contents/Resources/stockfish`
- iPhone / iPad 静态引擎：`Vendor/QipanStockfishBridge.xcframework`
- iPhone / iPad 模型：`Resources/Engines/Mobile/*.nnue`
- Stockfish 18 源码与本项目桥接修改：`ThirdParty/Stockfish/`

准备后的 macOS 引擎资源约 109 MB，当前 iOS/iPadOS Debug App 约 111 MB。Stockfish 与本项目使用 GPLv3 许可证，完整许可证、版权、作者和源码均随仓库提供。

## 如何体验

- 点击当前回合一方的棋子，棋盘会标出完整合法落点。
- 点击高亮格完成移动，随后自动切换回合并重新分析。
- 吃子目标用黄色圆环显示，普通落点用圆点显示。
- 分析面板采用中立的“上帝视角”，显示“白方优势”“黑方优势”或“局势均衡”，不使用正负分数暗示固定的白方视角。
- “最佳路线”显示当前走棋方的最佳着法、另一方的最佳应对和后续变化。
- 打开“两步最佳路线”，棋盘会用金色 `1` 和蓝色 `2` 显示最佳着法及最佳应对；采用连线与编号，不使用箭头。
- 打开“控制热力图”查看白方、黑方及双方重叠控制范围；颜色越深，表示控制该格的棋子越多。
- 点击“重新开始”恢复标准初始局面。

## 架构

工程拆分为四个独立静态库 Target，再由 App Target 组合：

| Target | 职责 |
| --- | --- |
| `GameCore` | 棋子、格子、局面、FEN、合法走法生成、对局状态与回合切换 |
| `Analysis` | 中立局势模型、最佳路线、控制范围和分析任务协调 |
| `Engine` | 统一引擎协议、macOS Stockfish/UCI 子进程适配器、iOS/iPadOS 内嵌静态引擎桥接 |
| `Interface` | 自适应 SwiftUI 棋盘、热力图和分析侧栏 |

依赖方向为：

```text
GameCore ← Engine ← Analysis
GameCore + Analysis + Engine ← Interface ← QipanChess App
```

## 平台引擎实现

### macOS

`Engine/StockfishProcessEngine.swift` 已实现真实 UCI 接入：

- 从 App Bundle 定位 Stockfish 18
- 在 App 沙盒内启动并管理子进程
- 完成 `uci`、`isready`、`position fen`、`go depth`、`quit` 通信
- 流式解析深度、耗时、节点数、局势分数、主变化和 `bestmove`
- 默认使用 2 个线程、64 MB Hash、搜索深度 16

### iPhone / iPad

由于 iOS 不允许采用 macOS 的子进程方案，移动端使用 App 内嵌方式：

- Stockfish 18 C++ 源码编译为静态 `XCFramework`
- 支持 iPhone/iPad 真机 arm64 和模拟器 arm64/x86_64
- C API 桥接到 `Engine/EmbeddedEngineBridge.swift`
- 两个 NNUE 模型作为只读 App 资源随安装包分发
- 与 macOS 共用同一套 `EngineResult`、中立评价和最佳路线面板

更新 Stockfish 源码或桥接后，可运行 `Scripts/prepare-engines.sh --force` 重新生成 macOS 引擎和移动端静态引擎包。

## 当前已实现

- macOS、iPhone、iPad 共用的一套 SwiftUI App
- 8×8 标准坐标棋盘和标准开局布局
- 点击选子、重新选子、移动、吃子、回合切换、最后一步高亮
- 不能让己方王暴露的完整合法着法过滤
- 将军相关合法性、王车易位、吃过路兵和自动升后
- 兵、马、象、车、后、王的控制范围计算和热力图
- macOS 子进程 Stockfish 18 实时分析
- iPhone/iPad App 内嵌 Stockfish 18 实时分析
- 中立局势显示，不固定采用白方视角
- 当前走棋方最佳着法、对手最佳应对、后续主变化
- 可开关的棋盘两步最佳路线连线与编号显示
- 搜索深度、耗时、节点数和引擎状态
- iOS/iPadOS 内嵌静态引擎、C++ 桥接与 NNUE 模型
- GameCore、Analysis、Engine、Interface 四层 Target 架构
- VoiceOver 棋盘格与棋子描述
- 已取消候选着法箭头功能

## 当前未实现

- 升变时选择车、马、象（当前自动升后）
- 三次重复、五十回合规则、棋子不足判和与完整棋谱历史
- 拖拽走子、悔棋/重做、棋盘翻转
- FEN/PGN 导入导出
- 多 PV、实时搜索进度和主动停止按钮
- 自然语言教学、大语言模型讲解
- App 图标、完整本地化、自动化测试 Target 和发布配置

## 已验证构建

当前版本已使用 Xcode 26.6 完成：

- macOS Debug 构建
- macOS Release 构建与签名验证
- macOS Stockfish 18 实际运行和实时分析验证
- iOS Simulator Debug 全新构建（arm64 与 x86_64）
- iOS Release 真机 arm64 构建
- iPhone 17 模拟器内嵌 Stockfish 深度 16 实际分析
- iPad Pro 13-inch 模拟器启动、走子和重新分析
- macOS 只携带可执行引擎，iOS/iPadOS 只携带静态引擎与 NNUE 模型的平台隔离

命令行复核示例：

```sh
xcodebuild -project QipanChess.xcodeproj -scheme QipanChess \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project QipanChess.xcodeproj -scheme QipanChess \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project QipanChess.xcodeproj -scheme QipanChess \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
