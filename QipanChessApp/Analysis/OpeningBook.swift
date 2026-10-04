import Foundation
import GameCore

public enum OpeningStudyRole: String, CaseIterable, Identifiable, Sendable {
    case whiteAttack
    case blackResponse

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .whiteAttack: "执白抢攻"
        case .blackResponse: "执黑应对"
        }
    }
}

public enum OpeningStyle: String, Sendable {
    case active = "主动"
    case aggressive = "激进"
    case solid = "稳健"
    case counterattack = "反击"
    case highRisk = "高风险"
}

public struct OpeningChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let role: OpeningStudyRole
    public let name: String
    public let subtitle: String
    public let eco: String
    public let style: OpeningStyle
    public let summary: String
    public let plan: String
    public let moves: [Move]

    public init(
        id: String,
        role: OpeningStudyRole,
        name: String,
        subtitle: String,
        eco: String,
        style: OpeningStyle,
        summary: String,
        plan: String,
        moves: [Move]
    ) {
        self.id = id
        self.role = role
        self.name = name
        self.subtitle = subtitle
        self.eco = eco
        self.style = style
        self.summary = summary
        self.plan = plan
        self.moves = moves
    }

    public func commonPrefixCount(with history: [Move]) -> Int {
        zip(moves, history).prefix { pair in pair.0 == pair.1 }.count
    }

    public func follows(history: [Move]) -> Bool {
        commonPrefixCount(with: history) == min(moves.count, history.count)
    }

    public func nextMove(after history: [Move]) -> Move? {
        guard follows(history: history), history.count < moves.count else { return nil }
        return moves[history.count]
    }

    public func progress(after history: [Move]) -> Double {
        guard !moves.isEmpty else { return 0 }
        return Double(min(commonPrefixCount(with: history), moves.count)) / Double(moves.count)
    }
}

public enum OpeningBook {
    public static let whiteAttacks: [OpeningChoice] = [
        choice(
            id: "italian",
            role: .whiteAttack,
            name: "意大利开局",
            subtitle: "快速出子 · 瞄准 f7",
            eco: "C50",
            style: .active,
            summary: "用王翼轻子迅速施压，同时保持中心稳定。",
            plan: "先完成出子与王车易位，再根据黑方布置选择 d4 或王翼进攻。",
            uci: "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d3 f8c5 e1g1 d7d6"
        ),
        choice(
            id: "scotch",
            role: .whiteAttack,
            name: "苏格兰开局",
            subtitle: "立即打开中心",
            eco: "C45",
            style: .active,
            summary: "尽早用 d4 挑战黑方中心，获得开放线路。",
            plan: "利用开放中心快速出子，避免重复移动同一枚棋子。",
            uci: "e2e4 e7e5 g1f3 b8c6 d2d4 e5d4 f3d4 g8f6 b1c3 f8b4"
        ),
        choice(
            id: "vienna",
            role: .whiteAttack,
            name: "维也纳开局",
            subtitle: "王翼蓄力 · 准备 f4",
            eco: "C25",
            style: .aggressive,
            summary: "先发展后马，再寻找 f4 推进和王翼空间。",
            plan: "不要只顾进攻，先保证王的安全和中心不过度暴露。",
            uci: "e2e4 e7e5 b1c3 g8f6 f2f4 d7d5 f4e5 f6e4 d2d3 e4c3"
        ),
        choice(
            id: "evans-gambit",
            role: .whiteAttack,
            name: "埃文斯弃兵",
            subtitle: "牺牲一兵换出子速度",
            eco: "C51",
            style: .aggressive,
            summary: "用 b4 争取节奏，快速建立中心并打开攻击线路。",
            plan: "补偿来自发展速度；如果进攻停顿，少兵劣势会逐渐显现。",
            uci: "e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 b2b4 c5b4 c2c3 b4c5 d2d4 e5d4 c3d4"
        ),
        choice(
            id: "kings-gambit",
            role: .whiteAttack,
            name: "王翼弃兵",
            subtitle: "开放 f 线 · 直接抢攻",
            eco: "C30",
            style: .highRisk,
            summary: "用 f4 诱导中心变化，争取王翼主动权。",
            plan: "这是高风险选择；优先发展棋子，不要连续用兵追逐。",
            uci: "e2e4 e7e5 f2f4 e5f4 g1f3 g7g5 h2h4 g5g4 f3e5 g8f6"
        ),
        choice(
            id: "queens-gambit",
            role: .whiteAttack,
            name: "后翼弃兵",
            subtitle: "用 c4 争夺中心",
            eco: "D30",
            style: .solid,
            summary: "并非单纯弃兵，而是用翼兵向黑方 d5 中心施压。",
            plan: "完成 Nc3、Nf3 与象的发展，逐渐增加中心压力。",
            uci: "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5 f8e7"
        )
    ]

    public static let blackResponses: [OpeningChoice] = [
        choice(
            id: "open-game",
            role: .blackResponse,
            name: "对称王兵",
            subtitle: "应对 1.e4 · 经典中心",
            eco: "C50",
            style: .solid,
            summary: "以 e5 正面争夺中心，快速发展双方轻子。",
            plan: "保持中心棋子的保护，尽快完成王车易位。",
            uci: "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 d2d3 f8c5"
        ),
        choice(
            id: "sicilian",
            role: .blackResponse,
            name: "西西里防御",
            subtitle: "应对 1.e4 · 不对称反击",
            eco: "B90",
            style: .counterattack,
            summary: "用 c5 从侧翼攻击 d4，制造不对称局面。",
            plan: "黑方通常在后翼反击，同时必须留意白方王翼攻势。",
            uci: "e2e4 c7c5 g1f3 d7d6 d2d4 c5d4 f3d4 g8f6 b1c3 a7a6"
        ),
        choice(
            id: "french",
            role: .blackResponse,
            name: "法兰西防御",
            subtitle: "应对 1.e4 · 封锁中心",
            eco: "C11",
            style: .counterattack,
            summary: "先用 e6 支撑 d5，建立坚固兵链。",
            plan: "核心反击点是 c5；注意及时解决后翼白格象的发展。",
            uci: "e2e4 e7e6 d2d4 d7d5 b1c3 g8f6 e4e5 f6d7 f2f4 c7c5"
        ),
        choice(
            id: "caro-kann",
            role: .blackResponse,
            name: "卡罗康防御",
            subtitle: "应对 1.e4 · 结构稳健",
            eco: "B18",
            style: .solid,
            summary: "用 c6 准备 d5，争取坚固结构并保留白格象。",
            plan: "完成中心交换后，稳步发展轻子，不急于制造战术。",
            uci: "e2e4 c7c6 d2d4 d7d5 b1c3 d5e4 c3e4 c8f5"
        ),
        choice(
            id: "qgd",
            role: .blackResponse,
            name: "后翼弃兵拒绝",
            subtitle: "应对 1.d4 · 守住中心",
            eco: "D30",
            style: .solid,
            summary: "用 e6 保护 d5，建立可靠中心。",
            plan: "先发展王翼并完成易位，再寻找 c5 或 e5 的中心反击。",
            uci: "d2d4 d7d5 c2c4 e7e6 b1c3 g8f6 c1g5 f8e7"
        ),
        choice(
            id: "slav",
            role: .blackResponse,
            name: "斯拉夫防御",
            subtitle: "应对 1.d4 · c6 支撑",
            eco: "D10",
            style: .solid,
            summary: "以 c6 加固 d5，同时保持白格象的出路。",
            plan: "发展节奏比贪兵重要，吃下 c4 后要准备归还。",
            uci: "d2d4 d7d5 c2c4 c7c6 g1f3 g8f6 b1c3 d5c4 a2a4 c8f5"
        ),
        choice(
            id: "kings-indian",
            role: .blackResponse,
            name: "王印度防御",
            subtitle: "应对 1.d4 · 王翼反击",
            eco: "E60",
            style: .counterattack,
            summary: "允许白方建立中心，再从王翼和深处反击。",
            plan: "完成 Bg7 与短易位后，依据中心选择 e5 或 c5。",
            uci: "d2d4 g8f6 c2c4 g7g6 b1c3 f8g7 e2e4 d7d6"
        ),
        choice(
            id: "nimzo-indian",
            role: .blackResponse,
            name: "尼姆佐印度防御",
            subtitle: "应对 1.d4 · 钉住后马",
            eco: "E20",
            style: .active,
            summary: "用 Bb4 施加压力，灵活控制 e4。",
            plan: "是否交换 c3 马取决于中心，避免无目的地放弃双象。",
            uci: "d2d4 g8f6 c2c4 e7e6 b1c3 f8b4"
        ),
        choice(
            id: "english-symmetry",
            role: .blackResponse,
            name: "英式开局应对",
            subtitle: "应对 1.c4 · 中心反击",
            eco: "A28",
            style: .active,
            summary: "用 e5 占据中心，限制白方后翼扩张。",
            plan: "自然发展王翼，并留意白方从 g2 象形成的长斜线压力。",
            uci: "c2c4 e7e5 b1c3 g8f6 g2g3 d7d5 c4d5 f6d5"
        ),
        choice(
            id: "reti-response",
            role: .blackResponse,
            name: "列蒂开局应对",
            subtitle: "应对 1.Nf3 · 占据中心",
            eco: "A05",
            style: .solid,
            summary: "直接用 d5 控制中心，再依据白方布局调整。",
            plan: "保持阵型灵活，不要过早锁定兵形。",
            uci: "g1f3 d7d5 g2g3 g8f6 f1g2 g7g6 e1g1 f8g7"
        )
    ]

    public static var all: [OpeningChoice] { whiteAttacks + blackResponses }

    public static func choices(for role: OpeningStudyRole, history: [Move]) -> [OpeningChoice] {
        let source = role == .whiteAttack ? whiteAttacks : blackResponses
        guard let firstMove = history.first else { return source }
        return source.filter { $0.moves.first == firstMove }
    }

    public static func opening(id: String?) -> OpeningChoice? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    public static func bestMatch(for history: [Move]) -> OpeningChoice? {
        guard !history.isEmpty else { return nil }
        return all
            .map { ($0, $0.commonPrefixCount(with: history)) }
            .filter { $0.1 > 0 }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0
    }

    private static func choice(
        id: String,
        role: OpeningStudyRole,
        name: String,
        subtitle: String,
        eco: String,
        style: OpeningStyle,
        summary: String,
        plan: String,
        uci: String
    ) -> OpeningChoice {
        OpeningChoice(
            id: id,
            role: role,
            name: name,
            subtitle: subtitle,
            eco: eco,
            style: style,
            summary: summary,
            plan: plan,
            moves: uci.split(separator: " ").compactMap { Move(uci: String($0)) }
        )
    }
}
