import Foundation
import GameCore

public struct AdvantagePoint: Identifiable, Equatable, Sendable {
    public let ply: Int
    public let advantage: PositionAdvantage
    public let classification: ReviewQuality?

    public init(ply: Int, advantage: PositionAdvantage, classification: ReviewQuality? = nil) {
        self.ply = ply
        self.advantage = advantage
        self.classification = classification
    }

    public var id: Int { ply }

    public var signedMagnitude: Double {
        switch advantage {
        case .balanced:
            return 0
        case .side(let color, let magnitude):
            return (color == .white ? 1 : -1) * min(magnitude, 8)
        case .mate(let color, _):
            return color == .white ? 8 : -8
        }
    }

    public func magnitude(from perspective: PieceColor) -> Double {
        signedMagnitude * (perspective == .white ? 1 : -1)
    }

    public var summary: String {
        switch advantage {
        case .balanced:
            return "局势均衡"
        case .side(let color, let magnitude):
            return "\(color.displayName)优势 \(String(format: "%.2f", magnitude))"
        case .mate(let color, let moves):
            return "\(color.displayName) \(moves) 步将杀"
        }
    }
}
