import Foundation

enum ChessAppMode: String, CaseIterable, Identifiable {
    case analysis
    case versusAI
    case treeBuilder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .analysis: "自由分析"
        case .versusAI: "与 AI 对弈"
        case .treeBuilder: "开局树构建"
        }
    }

    var systemImage: String {
        switch self {
        case .analysis: "scope"
        case .versusAI: "cpu"
        case .treeBuilder: "tree.fill"
        }
    }
}

enum AIDifficulty: String, CaseIterable, Identifiable {
    case relaxed
    case standard
    case challenge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: "入门"
        case .standard: "标准"
        case .challenge: "挑战"
        }
    }

    var depth: Int {
        switch self {
        case .relaxed: 6
        case .standard: 10
        case .challenge: 14
        }
    }

    var detail: String {
        switch self {
        case .relaxed: "计算较浅，适合熟悉走法"
        case .standard: "速度和棋力较均衡"
        case .challenge: "计算更深入，失误惩罚更强"
        }
    }
}
