import Foundation

public enum PieceColor: String, Codable, CaseIterable, Sendable {
    case white
    case black

    public var opposite: PieceColor {
        self == .white ? .black : .white
    }

    public var displayName: String {
        self == .white ? "白方" : "黑方"
    }
}

public enum PieceKind: String, Codable, CaseIterable, Sendable {
    case king
    case queen
    case rook
    case bishop
    case knight
    case pawn
}

public struct Piece: Hashable, Codable, Sendable {
    public let color: PieceColor
    public let kind: PieceKind

    public init(color: PieceColor, kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    public var symbol: String {
        switch (color, kind) {
        case (.white, .king): "♔"
        case (.white, .queen): "♕"
        case (.white, .rook): "♖"
        case (.white, .bishop): "♗"
        case (.white, .knight): "♘"
        case (.white, .pawn): "♙"
        case (.black, .king): "♚"
        case (.black, .queen): "♛"
        case (.black, .rook): "♜"
        case (.black, .bishop): "♝"
        case (.black, .knight): "♞"
        case (.black, .pawn): "♟"
        }
    }

    public var fenSymbol: Character {
        let base: Character = switch kind {
        case .king: "k"
        case .queen: "q"
        case .rook: "r"
        case .bishop: "b"
        case .knight: "n"
        case .pawn: "p"
        }
        return color == .white ? Character(String(base).uppercased()) : base
    }
}
