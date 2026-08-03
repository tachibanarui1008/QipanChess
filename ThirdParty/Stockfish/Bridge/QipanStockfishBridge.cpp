#include "QipanStockfishBridge.h"

#include <algorithm>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

#include "bitboard.h"
#include "engine.h"
#include "misc.h"
#include "position.h"
#include "search.h"
#include "uci.h"

namespace {

std::once_flag stockfishInitialization;

struct LatestAnalysis {
    std::string score;
    std::string bestMove;
    std::string principalVariation;
    std::string error;
    int depth = 0;
    int elapsedMilliseconds = 0;
    std::uint64_t nodes = 0;
};

void initializeStockfish() {
    std::call_once(stockfishInitialization, [] {
        Stockfish::Bitboards::init();
        Stockfish::Position::init();
    });
}

int parseScore(const std::string& score, QipanStockfishResult& result) {
    const auto separator = score.find(' ');
    if (separator == std::string::npos)
        return 0;

    const std::string kind = score.substr(0, separator);
    const long value = std::strtol(score.c_str() + separator + 1, nullptr, 10);
    result.scoreKind = kind == "mate" ? QipanStockfishScoreMate
                                       : QipanStockfishScoreCentipawns;
    result.scoreValue = static_cast<int32_t>(value);
    return 1;
}

}  // namespace

struct QipanStockfishContext {
    explicit QipanStockfishContext(const char *resourceExecutablePath) {
        initializeStockfish();
        engine = std::make_unique<Stockfish::Engine>(
            std::string(resourceExecutablePath ? resourceExecutablePath : "")
        );

        engine->set_on_update_no_moves([this](const Stockfish::Engine::InfoShort& info) {
            std::lock_guard<std::mutex> lock(stateMutex);
            latest.depth = info.depth;
            latest.score = Stockfish::UCIEngine::format_score(info.score);
        });

        engine->set_on_update_full([this](const Stockfish::Engine::InfoFull& info) {
            std::lock_guard<std::mutex> lock(stateMutex);
            latest.depth = info.depth;
            latest.score = Stockfish::UCIEngine::format_score(info.score);
            latest.elapsedMilliseconds = static_cast<int>(info.timeMs);
            latest.nodes = static_cast<std::uint64_t>(info.nodes);
            latest.principalVariation = std::string(info.pv);
        });

        engine->set_on_bestmove([this](std::string_view bestMove, std::string_view) {
            std::lock_guard<std::mutex> lock(stateMutex);
            latest.bestMove = std::string(bestMove);
        });

        engine->set_on_verify_networks([this](std::string_view message) {
            if (message.find("ERROR:") == std::string_view::npos)
                return;
            std::lock_guard<std::mutex> lock(stateMutex);
            latest.error = std::string(message);
        });
    }

    void reset() {
        std::lock_guard<std::mutex> lock(stateMutex);
        latest = LatestAnalysis{};
    }

    std::unique_ptr<Stockfish::Engine> engine;
    mutable std::mutex stateMutex;
    LatestAnalysis latest;
};

extern "C" QipanStockfishContext *qipan_stockfish_create(
    const char *resourceExecutablePath
) {
    return new QipanStockfishContext(resourceExecutablePath);
}

extern "C" void qipan_stockfish_destroy(QipanStockfishContext *context) {
    if (!context)
        return;
    context->engine->stop();
    context->engine->wait_for_search_finished();
    delete context;
}

extern "C" int32_t qipan_stockfish_analyze(
    QipanStockfishContext *context,
    const char *fen,
    int32_t depth,
    QipanStockfishResult *result
) {
    if (!context || !fen || !result)
        return 1;

    context->reset();
    context->engine->set_position(std::string(fen), std::vector<std::string>{});

    Stockfish::Search::LimitsType limits;
    limits.depth = std::clamp(static_cast<int>(depth), 1, 24);
    limits.startTime = Stockfish::now();

    context->engine->go(limits);
    context->engine->wait_for_search_finished();

    std::lock_guard<std::mutex> lock(context->stateMutex);
    if (!context->latest.error.empty())
        return 2;
    if (!parseScore(context->latest.score, *result)) {
        context->latest.error = "Stockfish 没有返回有效局势分数。";
        return 3;
    }

    result->depth = context->latest.depth;
    result->elapsedMilliseconds = context->latest.elapsedMilliseconds;
    result->nodes = context->latest.nodes;

    if (context->latest.bestMove.empty() && !context->latest.principalVariation.empty())
        context->latest.bestMove = context->latest.principalVariation.substr(0, 5);
    return 0;
}

extern "C" void qipan_stockfish_stop(QipanStockfishContext *context) {
    if (context)
        context->engine->stop();
}

extern "C" const char *qipan_stockfish_best_move(
    const QipanStockfishContext *context
) {
    return context ? context->latest.bestMove.c_str() : "";
}

extern "C" const char *qipan_stockfish_principal_variation(
    const QipanStockfishContext *context
) {
    return context ? context->latest.principalVariation.c_str() : "";
}

extern "C" const char *qipan_stockfish_last_error(
    const QipanStockfishContext *context
) {
    return context ? context->latest.error.c_str() : "Stockfish context is unavailable.";
}
