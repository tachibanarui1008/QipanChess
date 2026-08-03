import Foundation

public struct Move: Hashable, Codable, Sendable, Identifiable {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    public init?(uci: String) {
        guard uci.count >= 4 else { return nil }
        let characters = Array(uci)
        guard let from = Square(String(characters[0...1])),
              let to = Square(String(characters[2...3]))
        else { return nil }

        let promotion: PieceKind?
        if characters.count >= 5 {
            switch characters[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: return nil
            }
        } else {
            promotion = nil
        }
        self.init(from: from, to: to, promotion: promotion)
    }

    public var id: String {
        "\(from.notation)-\(to.notation)-\(promotion?.rawValue ?? "")"
    }

    public var notation: String {
        "\(from.notation) → \(to.notation)"
    }

    public var uci: String {
        let suffix: String
        switch promotion {
        case .queen: suffix = "q"
        case .rook: suffix = "r"
        case .bishop: suffix = "b"
        case .knight: suffix = "n"
        default: suffix = ""
        }
        return "\(from.notation)\(to.notation)\(suffix)"
    }
}
