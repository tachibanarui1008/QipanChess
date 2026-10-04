# ♟️ QipanChess

<p align="center">
  <strong>你需要一个国际象棋版的“褚嬴”，陪你安静地琢磨每一步吗？</strong>
</p>

<p align="center">
  一张棋盘，一个随时待命的分析搭档。<br>
  想独自拆解局面时，它安静地陪你分析；想来一盘实战时，它也能坐到棋盘对面。<br>
  不催你背谱，只在每一步之后告诉你：局势发生了什么，以及下一步还可以怎样想。
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

它不会抢走思考的乐趣。自由分析时，你可以替双方摆棋试招；与 AI 对弈时，你仍然自己选择每一步合法走法，Stockfish 18 负责应手并把局面照亮，让每一次决定都有反馈。

这里的“褚嬴”是一种陪伴式学棋体验的比喻，本项目与相关作品无关联。

## 它能陪你做什么

| 体验 | 它会怎样帮助你 |
| --- | --- |
| **一种棋风，一条建议** | 自选激进、稳健或保守，只计算当前棋风的一条路线 |
| **走一步，看两步** | 显示当前棋风的第一步推荐，以及对手最有力的下一步应对 |
| **从上帝视角看局势** | 直接告诉你当前哪一方占优，不强迫你把所有分数换算成固定的白方视角 |
| **看见棋盘上的力量** | 双方控制范围热力图让攻击、保护与争夺一眼可见 |
| **从开局开始建立计划** | 个人开局树随实战与研究增长，走法节点显示每步质量标记 |
| **随时从研究切换到实战** | 保留同一张棋盘和分析面板，一键切换为与 Stockfish 对弈 |
| **按自己的方式挑战 AI** | 自选执白或执黑，并在入门、标准、挑战三档棋力间切换 |
| **看懂优势如何形成** | 优势时间轴记录每次落子后的中立评价变化，而不只展示最后一个数字 |
| **先自己想，再看答案** | 所有分析显示都可以开关，适合先独立计算，再打开结果核对 |
| **同一盘棋，三种设备** | 一套原生 SwiftUI 工程，同时运行在 macOS、iPhone 和 iPad |
| **真实引擎，不是演示数字** | 三个平台均接入 Stockfish 18，走棋后会重新分析真实局面 |

### 最佳着箭头与每步评价

棋盘显示当前行棋方的三个候选着及其标记。自由分析只自动搜索当前局面，复用已有棋步评价；需要重新评价时，在棋谱下方展开“整盘深入分析”。AI 对弈仍自动评价落子。局势走势跟随当前行棋方视角，上方表示该方占优。

### 个人开局树

“开局树构建”提供从底部向上生长的分枝画布，按开局终点局势整理白方有利、黑方有利的路线，均衡或评分不足的路线单列保留。已有节点直接复用保存的评分，不重复运行引擎；根据所选分类、起始局面和第一步自动匹配树，无需手动选择；试走后点击保存，自动新增分枝或建立新树。构建页可按需获取三个候选着，按引擎顺序与质量标记显示，点击直接落子；只展示当前行棋方走法，已计算的局面复用缓存。支持修改走法、保存分枝、重命名、删除与撤销，以及节点备注、主线及隐藏／恢复，暖白与深灰节点区分落子方。支持拖动、缩放、适应全树和聚焦当前路线；自由分析直接显示当前分枝。

“补充开局资源”可按用户名拉取全部公开历史，按开局终点优势与第一步整理个人开局树；构建界面只展示开局路线与自己的备注。后台评分可暂停并在重启后恢复；全部本地棋局和树均可离线使用。

### “与 AI 对弈”模式

顶部模式开关可以在“自由分析”和“与 AI 对弈”之间切换。进入对弈后：

- 你可以执白先行，也可以执黑让 Stockfish 自动走出第一步。
- 入门、标准、挑战三档难度对应不同搜索深度，既能轻松练习，也能认真挑战。
- AI 棋风可随时切换为激进、稳健或保守；界面和引擎始终只处理当前选中的一条路线。
- 切换棋风时只重新计算新棋风，不会先生成另外两条路线。
- 稳健棋风直接请求 Stockfish 单一最佳线；激进和保守棋风先由本地规则选择唯一合法着法，再由 Stockfish 单线计算对手最佳回应。
- 轮到你时仍可自由选择任意合法走法；轮到 AI 时棋盘会暂时锁定，避免误操作。
- 悔棋会退回一个完整对弈回合，让你重新选择自己的上一步，而不是马上重复同一局面。
- 原有的中立评价、优势时间轴、控制热力图和策略箭头开关全部保留。

## 本地棋局、整盘复盘与个人开局树

主界面提供 **自由分析、与 AI 对弈、开局树构建**：

- **棋局库**：自动保存、重启恢复、PGN/FEN 导入、PGN 导出、逐步回放、备注和保留分析分支。
- **棋谱分析**：自由分析不额外运行逐步评分，也不显示最佳着／实战变化对比。棋谱下方可选择快速／标准／深入整盘分析，按完整主线重新计算并更新棋盘标记、棋谱和走势；AI 对弈保留自动棋步评价。评分结果保存到本机。
- **个人开局树**：多棵主题、持续增长、节点标记与备注、主线编辑、隐藏恢复，以及公开棋谱资源导入与白黑开局整理。
- **棋规补充**：四种升变选择、自动和棋判断，以及三次重复／五十回合申请和棋。

评价独立于 AI 难度与棋风，使用胜／和／负预期得分损失和公开分档。妙着为本地启发式识别，不宣称复制 Chess.com 的专有玩家等级模型。主题树来自个人实战和研究，不是固定课程。

详细用法、分析阈值与限制见 [离线学棋说明](docs/OFFLINE_STUDY.md)。

## 现在，它已经是一款可以运行的 App

这不是一张概念图，也不是只有界面的空壳。当前版本已经具备：

- 8×8 标准棋盘与完整开局布局
- 自由分析、与 AI 对弈、开局树构建三种模式随时切换
- 对弈模式可选执白/执黑、三档难度和三种 AI 棋风，并由 Stockfish 自动应手
- 点击选子、重新选子、移动、吃子与回合切换
- 不能让己方王暴露的完整合法着法过滤
- 将军判断、王车易位、吃过路兵与四种升变选择
- 最后一步、普通落点与吃子目标高亮
- 白方、黑方及双方重叠控制范围热力图
- 中立局势评价、搜索深度、耗时与节点数
- 激进、稳健、保守棋风切换及单路线两步预测
- 当前棋风策略卡片与单色棋盘箭头
- 执白抢攻与执黑应对开局 Dock、路线识别和定式提示
- 完整局面悔棋（包括回合、易位权和吃过路兵状态）
- 对弈模式整回合悔棋，直接回到玩家上一次决策点
- 棋盘 180° 黑白反转，坐标和分析箭头同步旋转
- 每步中立评价组成的优势时间轴，悔棋后同步回退
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
- 默认使用 2 个线程、64 MB Hash；所有策略预测只使用单 PV
- 激进/保守的根着法由本地棋风规则选择，Stockfish 只计算这一条的最佳回应

### iPhone / iPad

iOS 与 iPadOS 不采用子进程，而是把 Stockfish 直接嵌入 App：

- Stockfish 18 C++ 编译为静态 `XCFramework`
- 支持 arm64 真机
- 支持 arm64 / x86_64 模拟器
- C API 桥接到 Swift 引擎适配器
- 内嵌桥接支持可调 MultiPV、WDL 与多条 PV 一次返回
- 移动端策略搜索深度 18，兼顾棋力、温度与续航
- NNUE 模型作为只读 App 资源随安装包分发
- 与 macOS 共用同一套分析结果与界面

Stockfish 只存在于工程和最终 App 内，不会被安装到 `/usr/local` 或其他系统目录。

## 清晰的四层架构

项目不是把所有逻辑塞进一个 SwiftUI View，而是拆分为四个独立静态库 Target：

| Target | 职责 |
| --- | --- |
| `GameCore` | 棋子、格子、局面、FEN、合法着法与回合状态 |
| `Analysis` | 中立评价、单棋风路线选择、控制范围与分析任务协调 |
| `Engine` | 统一引擎协议、macOS UCI 子进程、iOS/iPadOS 内嵌桥接 |
| `Interface` | 自适应 SwiftUI 棋盘、热力图与分析面板 |

```text
GameCore ← Engine ← Analysis
GameCore + Analysis + Engine ← Interface ← QipanChess App
```

这让棋规、引擎和界面彼此独立，也为未来加入棋谱、复盘、教学提示或更强的解释层留下空间。

## 接下来还想做什么

QipanChess 当前更像一位安静、精确的分析陪练。未来可以继续补上：

- 拖拽走子
- 更完整的死局判断与赛制设置
- 完整 NAG 编辑
- 引擎当前搜索的即时停止
- 更深入的妙棋识别与树的跨设备同步
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

自由分析左侧直接展示开局树，点击节点同步棋盘；棋盘上方的“摆棋”可自由放置或移除棋子，指定行棋方、易位权或载入 FEN，通过局面校验后开始分析。
