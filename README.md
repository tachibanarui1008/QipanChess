# ♟️ QipanChess

<p align="center">
  <strong>你需要一个国际象棋版的“褚嬴”，陪你安静地琢磨每一步吗？</strong>
</p>

<p align="center">
  一张棋盘，一个随时待命的分析搭档。<br>
  不替你下棋，不催你背谱，只在你落子之后告诉你：局势发生了什么，以及下一步还可以怎样想。
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-111111?logo=apple">
  <img alt="iPadOS 17+" src="https://img.shields.io/badge/iPadOS-17%2B-111111?logo=apple">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-F05138?logo=swift&logoColor=white">
  <img alt="Stockfish 18" src="https://img.shields.io/badge/Engine-Stockfish%2018-5D9948">
  <img alt="GPL v3" src="https://img.shields.io/badge/License-GPL%20v3-blue">
</p>

---

## 一个人学棋，也应该有人陪你复盘

很多时候，我们不是没有棋盘，也不是没有棋谱，而是缺少一个愿意一直待在旁边、把每个局面重新看一遍的搭档。

**QipanChess 想做的，就是这样一件简单的事：**

> 让你一个人摆棋、试棋、走棋时，也能像身边坐着一位“褚嬴式”的陪练——看见局势，看见威胁，也看见你还没想到的下一步。

它不会抢走思考的乐趣。你仍然自己选棋、自己落子、自己判断；Stockfish 18 只负责把局面照亮，让每一次试探都有反馈。

这里的“褚嬴”是一种陪伴式学棋体验的比喻，本项目与相关作品无关联。

## 它能陪你做什么

| 体验 | 它会怎样帮助你 |
| --- | --- |
| **走一步，看两步** | 实时显示当前一方的最佳着法，以及对手最有力的下一步应对 |
| **从上帝视角看局势** | 直接告诉你当前哪一方占优，不强迫你把所有分数换算成固定的白方视角 |
| **看见棋盘上的力量** | 双方控制范围热力图让攻击、保护与争夺一眼可见 |
| **先自己想，再看答案** | 所有分析显示都可以开关，适合先独立计算，再打开结果核对 |
| **同一盘棋，三种设备** | 一套原生 SwiftUI 工程，同时运行在 macOS、iPhone 和 iPad |
| **真实引擎，不是演示数字** | 三个平台均接入 Stockfish 18，走棋后会重新分析真实局面 |

### 棋盘上的“两步最佳路线”

打开开关后，棋盘会直接标出：

- 金色 `1`：当前走棋方的最佳着法
- 蓝色 `2`：对手的最佳应对

路线使用简洁的连线、圆环和编号，不使用箭头，也不会挡住棋盘点击。关闭开关后，棋盘立即恢复干净，继续留给你自己思考。

## 现在，它已经是一款可以运行的 App

这不是一张概念图，也不是只有界面的空壳。当前版本已经具备：

- 8×8 标准棋盘与完整开局布局
- 点击选子、重新选子、移动、吃子与回合切换
- 不能让己方王暴露的完整合法着法过滤
- 将军判断、王车易位、吃过路兵与自动升后
- 最后一步、普通落点与吃子目标高亮
- 白方、黑方及双方重叠控制范围热力图
- 中立局势评价、搜索深度、耗时与节点数
- 当前最佳着法、对手最佳应对与后续主变化
- 可开关的棋盘两步最佳路线
- VoiceOver 棋盘格与棋子描述

## 30 秒开始体验

### 1. 获取项目

```sh
git clone https://github.com/tachibanarui1008/QipanChess.git
cd QipanChess
```

### 2. 一键准备三个平台的引擎

```sh
./Scripts/prepare-engines.sh
```

脚本会自动：

- 从 Stockfish 官方服务器下载两个 NNUE 模型
- 使用 SHA-256 校验模型完整性
- 为当前 Apple 芯片或 Intel Mac 编译 Stockfish 18
- 检查并在需要时重建 iPhone/iPad 静态 XCFramework

GitHub 普通仓库不直接保存超过 100 MiB 的引擎成品与大型模型，因此不需要 Git LFS。需要强制重新生成全部引擎资源时，运行：

```sh
./Scripts/prepare-engines.sh --force
```

### 3. 在 Xcode 里运行

1. 打开 `QipanChess.xcodeproj`。
2. 选择 `QipanChess` Scheme。
3. 选择运行设备：
   - macOS：`My Mac`
   - iPhone：任意 iPhone 模拟器或真机
   - iPad：任意 iPad 模拟器或真机
4. 点击 Run（▶）或按 `⌘R`。

真机运行需要在 QipanChess Target 的 Signing & Capabilities 中选择自己的开发团队；Mac 与模拟器调试不需要额外签名配置。

## 三个平台，同一颗棋力核心

### macOS

macOS 使用真实的 UCI 子进程方式接入 Stockfish 18：

- 从 App Bundle 定位引擎
- 管理 Stockfish 进程与生命周期
- 完成 `uci`、`isready`、`position fen`、`go depth`、`quit` 通信
- 流式解析局势分数、深度、节点数、主变化与 `bestmove`
- 默认使用 2 个线程、64 MB Hash、搜索深度 16

### iPhone / iPad

iOS 与 iPadOS 不采用子进程，而是把 Stockfish 直接嵌入 App：

- Stockfish 18 C++ 编译为静态 `XCFramework`
- 支持 arm64 真机
- 支持 arm64 / x86_64 模拟器
- C API 桥接到 Swift 引擎适配器
- NNUE 模型作为只读 App 资源随安装包分发
- 与 macOS 共用同一套分析结果与界面

Stockfish 只存在于工程和最终 App 内，不会被安装到 `/usr/local` 或其他系统目录。

## 清晰的四层架构

项目不是把所有逻辑塞进一个 SwiftUI View，而是拆分为四个独立静态库 Target：

| Target | 职责 |
| --- | --- |
| `GameCore` | 棋子、格子、局面、FEN、合法着法与回合状态 |
| `Analysis` | 中立评价、最佳路线、控制范围与分析任务协调 |
| `Engine` | 统一引擎协议、macOS UCI 子进程、iOS/iPadOS 内嵌桥接 |
| `Interface` | 自适应 SwiftUI 棋盘、热力图与分析面板 |

```text
GameCore ← Engine ← Analysis
GameCore + Analysis + Engine ← Interface ← QipanChess App
```

这让棋规、引擎和界面彼此独立，也为未来加入棋谱、复盘、教学提示或更强的解释层留下空间。

## 接下来还想做什么

QipanChess 当前更像一位安静、精确的分析陪练。未来可以继续补上：

- 升变时自由选择车、马、象
- 三次重复、五十回合与棋子不足判和
- 拖拽走子、悔棋、重做与棋盘翻转
- FEN / PGN 导入导出
- 多 PV、实时搜索进度与主动停止
- 棋谱历史与逐步复盘
- 更自然的局面解释与教学提示
- App 图标、完整本地化与自动化测试

当前版本没有接入大语言模型，也不会假装理解你的情绪或棋风。它先把棋盘、规则与分析做好——这是成为真正“陪你学棋的人”之前，最重要的一步。

## 已验证

当前版本已经完成：

- macOS Debug / Release 构建
- macOS Stockfish 18 UCI 启动与实时分析
- iOS Simulator Debug 全新构建（arm64 / x86_64）
- iOS / iPadOS Release 真机 arm64 构建
- iPhone 模拟器 Stockfish 深度 16 分析
- iPad 模拟器启动、走棋与重新分析
- 一键脚本完整强制重编译验证

命令行复核：

```sh
xcodebuild -project QipanChess.xcodeproj -scheme QipanChess \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project QipanChess.xcodeproj -scheme QipanChess \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project QipanChess.xcodeproj -scheme QipanChess \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## 开源与致谢

QipanChess 使用 GPL v3 许可证发布，因为项目集成并分发 Stockfish。完整许可证、Stockfish 作者信息与对应源码都已随仓库提供。

- 项目许可证：[`LICENSE.md`](LICENSE.md)
- GPL v3 全文：[`ThirdParty/Stockfish/sf_18/Copying.txt`](ThirdParty/Stockfish/sf_18/Copying.txt)
- Stockfish 作者：[`ThirdParty/Stockfish/sf_18/AUTHORS`](ThirdParty/Stockfish/sf_18/AUTHORS)

---

<p align="center">
  <strong>一个人也可以认真学棋。</strong><br>
  <sub>摆下棋子，先听自己的判断，再看看引擎眼中的世界。</sub>
</p>
