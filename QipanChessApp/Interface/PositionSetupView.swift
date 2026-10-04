import SwiftUI
import GameCore

struct PositionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pieces: [Square: Piece]
    @State private var turn: PieceColor
    @State private var rights: CastlingRights
    @State private var brush: Piece? = Piece(color: .white, kind: .pawn)
    @State private var error: String?
    @State private var fen = ""
    @State private var enPassant: Square?
    @State private var halfmove: Int
    @State private var ply: Int
    let onApply: (GamePosition) -> Void
    init(position: GamePosition, onApply: @escaping (GamePosition) -> Void) {
        _pieces = State(initialValue: position.pieces); _turn = State(initialValue: position.sideToMove)
        _rights = State(initialValue: position.castlingRights); _enPassant = State(initialValue: position.enPassantTarget)
        _halfmove = State(initialValue: position.halfmoveClock); _ply = State(initialValue: position.plyCount)
        self.onApply = onApply
    }
    private var draft: GamePosition {
        GamePosition(pieces: pieces, sideToMove: turn, plyCount: (ply / 2) * 2 + (turn == .black ? 1 : 0), castlingRights: rights, enPassantTarget: enPassant, halfmoveClock: halfmove)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button("取消") { dismiss() }; Spacer(); Text("摆棋分析").font(.headline); Spacer()
                    Button("开始分析") {
                        do { let position = try PositionSetup.validate(draft); onApply(position); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                }
                Text("先选棋子，再点棋盘放置；选择橡皮擦可移除棋子。").font(.caption).foregroundStyle(.secondary)
                ForEach(PieceColor.allCases, id: \.self) { color in
                    HStack {
                        ForEach(PieceKind.allCases, id: \.self) { kind in
                            let piece = Piece(color: color, kind: kind)
                            Button { brush = piece } label: {
                                Text(piece.symbol).font(.system(size: 30)).frame(maxWidth: .infinity).padding(.vertical, 3)
                                    .background(brush == piece ? AppTheme.accent.opacity(0.3) : .clear).clipShape(RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).accessibilityLabel(color.displayName + String(piece.fenSymbol))
                        }
                    }
                }
                HStack {
                    Button { brush = nil } label: { Label("橡皮擦", systemImage: "eraser") }.tint(brush == nil ? AppTheme.accent : .secondary)
                    Spacer()
                    Button("清空棋盘") { pieces = [:]; rights = []; enPassant = nil; halfmove = 0; error = nil }
                    Button("初始局面") { assign(.starting) }
                }.font(.caption)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 0) {
                    ForEach(0..<64, id: \.self) { index in
                        let square = Square(file: index % 8, rank: 7 - index / 8)!
                        Button {
                            if let brush, brush.kind == .king { pieces = pieces.filter { $0.value != brush } }
                            pieces[square] = brush; rights = []; enPassant = nil; halfmove = 0; error = nil
                        } label: {
                            ZStack {
                                ((square.file + square.rank) % 2 == 0 ? AppTheme.boardDark : AppTheme.boardLight)
                                Text(pieces[square]?.symbol ?? "").font(.system(size: 34)).foregroundStyle(.black)
                            }.aspectRatio(1, contentMode: .fit)
                        }.buttonStyle(.plain).accessibilityLabel(square.notation + " " + (pieces[square]?.symbol ?? "空格"))
                    }
                }.frame(maxWidth: 430).clipShape(RoundedRectangle(cornerRadius: 8))
                Picker("轮到哪方走", selection: Binding(get: { turn }, set: { turn = $0; enPassant = nil })) { Text("白方走").tag(PieceColor.white); Text("黑方走").tag(PieceColor.black) }.pickerStyle(.segmented)
                DisclosureGroup("易位权与 FEN") {
                    VStack(alignment: .leading) {
                        rightToggle("白方短易位", .whiteKingSide); rightToggle("白方长易位", .whiteQueenSide)
                        rightToggle("黑方短易位", .blackKingSide); rightToggle("黑方长易位", .blackQueenSide)
                        TextField("粘贴 FEN 局面", text: $fen).textFieldStyle(.roundedBorder)
                        Button("载入 FEN") { do { assign(try PositionSetup.validate(GamePosition(fen: fen))) } catch { self.error = error.localizedDescription } }
                    }
                }.font(.caption)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(18).frame(maxWidth: 560)
        }.frame(minWidth: 320, idealWidth: 540, minHeight: 500, idealHeight: 780)
    }
    private func rightToggle(_ name: String, _ right: CastlingRights) -> some View {
        Toggle(name, isOn: Binding(get: { rights.contains(right) }, set: { if $0 { rights.insert(right) } else { rights.remove(right) } }))
    }
    private func assign(_ position: GamePosition) {
        pieces = position.pieces; turn = position.sideToMove; rights = position.castlingRights
        enPassant = position.enPassantTarget; halfmove = position.halfmoveClock; ply = position.plyCount; error = nil
    }
}
