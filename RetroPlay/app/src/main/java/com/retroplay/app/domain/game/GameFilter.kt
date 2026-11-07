package com.retroplay.app.domain.game

import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.GameCategory

object GameFilter {
    /** Filters by category (null = all) and a case-insensitive query over title and short title. */
    fun apply(games: List<Game>, query: String, category: GameCategory?): List<Game> {
        val q = query.trim()
        return games.filter { game ->
            (category == null || game.category == category) &&
                (q.isEmpty() || game.title.contains(q, ignoreCase = true) || game.shortTitle.equals(q, ignoreCase = true))
        }
    }

    fun recentlyPlayed(games: List<Game>, limit: Int = 6): List<Game> =
        games.filter { it.lastPlayedAtEpochMillis != null }
            .sortedByDescending { it.lastPlayedAtEpochMillis }
            .take(limit)
}
