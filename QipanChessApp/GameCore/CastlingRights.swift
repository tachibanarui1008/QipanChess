import Foundation

public struct CastlingRights: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let whiteKingSide = CastlingRights(rawValue: 1 << 0)
    public static let whiteQueenSide = CastlingRights(rawValue: 1 << 1)
    public static let blackKingSide = CastlingRights(rawValue: 1 << 2)
    public static let blackQueenSide = CastlingRights(rawValue: 1 << 3)
    public static let all: CastlingRights = [
        .whiteKingSide, .whiteQueenSide, .blackKingSide, .blackQueenSide
    ]

    public func containsKingSide(for color: PieceColor) -> Bool {
        contains(color == .white ? .whiteKingSide : .blackKingSide)
    }

    public func containsQueenSide(for color: PieceColor) -> Bool {
        contains(color == .white ? .whiteQueenSide : .blackQueenSide)
    }

    public var fen: String {
        var value = ""
        if contains(.whiteKingSide) { value += "K" }
        if contains(.whiteQueenSide) { value += "Q" }
        if contains(.blackKingSide) { value += "k" }
        if contains(.blackQueenSide) { value += "q" }
        return value.isEmpty ? "-" : value
    }
}
