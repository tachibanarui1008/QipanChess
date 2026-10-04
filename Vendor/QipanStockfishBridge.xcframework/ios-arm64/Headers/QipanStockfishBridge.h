#ifndef QIPAN_STOCKFISH_BRIDGE_H
#define QIPAN_STOCKFISH_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QipanStockfishContext QipanStockfishContext;

typedef enum QipanStockfishScoreKind {
    QipanStockfishScoreCentipawns = 0,
    QipanStockfishScoreMate = 1
} QipanStockfishScoreKind;

typedef struct QipanStockfishResult {
    int32_t scoreKind;
    int32_t scoreValue;
    int32_t depth;
    int32_t elapsedMilliseconds;
    uint64_t nodes;
} QipanStockfishResult;

typedef struct QipanStockfishVariation {
    int32_t rank;
    int32_t scoreKind;
    int32_t scoreValue;
    int32_t depth;
    int32_t winPermille;
    int32_t drawPermille;
    int32_t lossPermille;
} QipanStockfishVariation;

QipanStockfishContext *qipan_stockfish_create(const char *resourceExecutablePath);
void qipan_stockfish_destroy(QipanStockfishContext *context);

int32_t qipan_stockfish_analyze(
    QipanStockfishContext *context,
    const char *fen,
    int32_t depth,
    int32_t multiPV,
    QipanStockfishResult *result
);

// History and root-move restriction preserve draw context and comparable searches.
int32_t qipan_stockfish_analyze_position(
    QipanStockfishContext *context,
    const char *initialFen,
    const char *historyMoves,
    const char *rootMoves,
    int32_t depth,
    int32_t multiPV,
    QipanStockfishResult *result
);

void qipan_stockfish_stop(QipanStockfishContext *context);

const char *qipan_stockfish_best_move(const QipanStockfishContext *context);
const char *qipan_stockfish_principal_variation(const QipanStockfishContext *context);
int32_t qipan_stockfish_variation_count(const QipanStockfishContext *context);
int32_t qipan_stockfish_variation(
    const QipanStockfishContext *context,
    int32_t index,
    QipanStockfishVariation *variation
);
const char *qipan_stockfish_variation_principal_variation(
    const QipanStockfishContext *context,
    int32_t index
);
const char *qipan_stockfish_last_error(const QipanStockfishContext *context);

#ifdef __cplusplus
}
#endif

#endif
