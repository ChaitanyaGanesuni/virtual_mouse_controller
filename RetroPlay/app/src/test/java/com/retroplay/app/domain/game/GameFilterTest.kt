package com.retroplay.app.domain.game

import com.retroplay.app.domain.model.GameCategory
import org.junit.Assert.assertEquals
import org.junit.Test

class GameFilterTest {
    private val games = GameCatalogue.initialGames

    @Test fun emptyQueryAndNoCategoryReturnsEverything() {
        assertEquals(games, GameFilter.apply(games, "  ", null))
    }

    @Test fun filtersByCategory() {
        assertEquals(listOf("ea-sports-cricket-07"), GameFilter.apply(games, "", GameCategory.CRICKET).map { it.id })
    }

    @Test fun queryMatchesTitleCaseInsensitivelyAndShortTitleExactly() {
        assertEquals(listOf("gta-vice-city"), GameFilter.apply(games, "vice", null).map { it.id })
        assertEquals(listOf("gta-san-andreas"), GameFilter.apply(games, "sa", GameCategory.GTA).map { it.id })
        assertEquals(emptyList<String>(), GameFilter.apply(games, "vice", GameCategory.CRICKET).map { it.id })
    }

    @Test fun recentlyPlayedSortsNewestFirstAndSkipsNeverPlayed() {
        val played = games.mapIndexed { i, g -> if (i < 3) g.copy(lastPlayedAtEpochMillis = i * 1000L) else g }
        assertEquals(listOf(games[2].id, games[1].id, games[0].id), GameFilter.recentlyPlayed(played).map { it.id })
    }
}
