#include "QipanStockfishBridge.h"

#include <algorithm>
#include <cstdlib>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
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

struct LatestVariation {
    std::string score;
    std::string principalVariation;
    std::string wdl;
    int depth = 0;
    int rank = 1;
};

struct LatestAnalysis {
    std::string score;
    std::string bestMove;
    std::string principalVariation;
    std::string error;
    int depth = 0;
    int elapsedMilliseconds = 0;
    std::uint64_t nodes = 0;
    std::map<int, LatestVariation> variations;
};

void initializeStockfish() {
    std::call_once(stockfishInitialization, [] {
        Stockfish::Bitboards::init();
        Stockfish::Position::init();
    });
}

int parseScoreValues(const std::string& score, int32_t& kindValue, int32_t& scoreValue) {
    const auto separator = score.find(' ');
    if (separator == std::string::npos)
        return 0;

    const std::string kind = score.substr(0, separator);
    const long value = std::strtol(score.c_str() + separator + 1, nullptr, 10);
    kindValue = kind == "mate" ? QipanStockfishScoreMate
                                : QipanStockfishScoreCentipawns;
    scoreValue = static_cast<int32_t>(value);
    return 1;
}

int parseScore(const std::string& score, QipanStockfishResult& result) {
    return parseScoreValues(score, result.scoreKind, result.scoreValue);
}

void parseWDL(
    const std::string& wdl,
    int32_t& wins,
    int32_t& draws,
    int32_t& losses
) {
    wins = draws = losses = -1;
    std::istringstream stream(wdl);
    stream >> wins >> draws >> losses;
    if (stream.fail())
        wins = draws = losses = -1;
}

}  // namespace

struct QipanStockfishContext {
    explicit QipanStockfishContext(const char *resourceExecutablePath) {
        initializeStockfish();
        engine = std::make_unique<Stockfish::Engine>(
            std::string(resourceExecutablePath ? resourceExecutablePath : "")
        );

        std::istringstream showWDL("name UCI_ShowWDL value true");
        engine->get_options().setoption(showWDL);

        engine->set_on_update_no_moves([this](const Stockfish::Engine::InfoShort& info) {
            std::lock_guard<std::mutex> lock(stateMutex);
            latest.depth = info.depth;
            latest.score = Stockfish::UCIEngine::format_score(info.score);
        });

        engine->set_on_update_full([this](const Stockfish::Engine::InfoFull& info) {
            if (!info.bound.empty()) return;
            std::lock_guard<std::mutex> lock(stateMutex);
            LatestVariation& variation = latest.variations[static_cast<int>(info.multiPV)];
            variation.rank = static_cast<int>(info.multiPV);
            variation.depth = info.depth;
            variation.score = Stockfish::UCIEngine::format_score(info.score);
            variation.wdl = std::string(info.wdl);
            variation.principalVariation = std::string(info.pv);

            if (info.multiPV == 1) {
                latest.depth = info.depth;
                latest.score = variation.score;
                latest.elapsedMilliseconds = static_cast<int>(info.timeMs);
                latest.nodes = static_cast<std::uint64_t>(info.nodes);
                latest.principalVariation = variation.principalVariation;
            }
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
    QipanStockfishContext *context, const char *fen, int32_t depth,
    int32_t multiPV, QipanStockfishResult *result
) {
    return qipan_stockfish_analyze_position(context, fen, "", "", depth, multiPV, result);
}

extern "C" int32_t qipan_stockfish_analyze_position(
    QipanStockfishContext *context, const char *fen,
    const char *historyMoves, const char *rootMoves,
    int32_t depth, int32_t multiPV, QipanStockfishResult *result
) {
    if (!context || !fen || !result)
        return 1;

    context->reset();
    std::istringstream multiPVOption(
        "name MultiPV value " + std::to_string(std::clamp(static_cast<int>(multiPV), 1, 8))
    );
    context->engine->get_options().setoption(multiPVOption);
    auto parseMoves = [](const char *text) {
        std::vector<std::string> moves;
        std::istringstream stream(text ? text : "");
        std::string move;
        while (stream >> move) moves.push_back(move);
        return moves;
    };
    context->engine->set_position(std::string(fen), parseMoves(historyMoves));

    Stockfish::Search::LimitsType limits;
    limits.depth = std::clamp(static_cast<int>(depth), 1, 24);
    limits.startTime = Stockfish::now();
    limits.searchmoves = parseMoves(rootMoves);

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

extern "C" int32_t qipan_stockfish_variation_count(
    const QipanStockfishContext *context
) {
    if (!context)
        return 0;
    std::lock_guard<std::mutex> lock(context->stateMutex);
    return static_cast<int32_t>(context->latest.variations.size());
}

extern "C" int32_t qipan_stockfish_variation(
    const QipanStockfishContext *context,
    int32_t index,
    QipanStockfishVariation *variation
) {
    if (!context || !variation || index < 0)
        return 1;

    std::lock_guard<std::mutex> lock(context->stateMutex);
    if (static_cast<std::size_t>(index) >= context->latest.variations.size())
        return 2;

    auto iterator = context->latest.variations.begin();
    std::advance(iterator, index);
    const LatestVariation& source = iterator->second;

    variation->rank = source.rank;
    variation->depth = source.depth;
    if (!parseScoreValues(source.score, variation->scoreKind, variation->scoreValue))
        return 3;
    parseWDL(
        source.wdl,
        variation->winPermille,
        variation->drawPermille,
        variation->lossPermille
    );
    return 0;
}

extern "C" const char *qipan_stockfish_variation_principal_variation(
    const QipanStockfishContext *context,
    int32_t index
) {
    if (!context || index < 0)
        return "";

    std::lock_guard<std::mutex> lock(context->stateMutex);
    if (static_cast<std::size_t>(index) >= context->latest.variations.size())
        return "";
    auto iterator = context->latest.variations.begin();
    std::advance(iterator, index);
    return iterator->second.principalVariation.c_str();
}

extern "C" const char *qipan_stockfish_last_error(
    const QipanStockfishContext *context
) {
    return context ? context->latest.error.c_str() : "Stockfish context is unavailable.";
}
