package com.retroplay.app.domain.game

import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.ExecutionType
import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.model.GamePlatform
import com.retroplay.app.domain.model.InstallationStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GameCatalogueTest {
    private val games = GameCatalogue.initialGames

    @Test fun containsTheRequestedSixGames() {
        assertEquals(
            listOf(
                "EA Sports Cricket 07",
                "Grand Theft Auto III",
                "Grand Theft Auto: Vice City",
                "Grand Theft Auto: San Andreas",
                "Grand Theft Auto IV",
                "Grand Theft Auto V",
            ),
            games.map { it.title },
        )
        assertEquals(1, games.count { it.category == GameCategory.CRICKET })
        assertEquals(5, games.count { it.category == GameCategory.GTA })
    }

    @Test fun idsAreUnique() {
        assertEquals(games.size, games.map { it.id }.toSet().size)
    }

    @Test fun pcGamesStartUntestedAndUnimported() {
        games.filter { it.originalPlatform == GamePlatform.WINDOWS_PC }.forEach {
            assertEquals(it.title, CompatibilityStatus.NOT_TESTED, it.compatibilityStatus)
            assertEquals(it.title, InstallationStatus.NOT_IMPORTED, it.installationStatus)
            assertEquals(it.title, ExecutionType.EXTERNAL_EMULATOR, it.executionType)
        }
    }

    @Test fun usesGeneratedPlaceholderArtworkAndNoUserData() {
        games.forEach {
            assertTrue(it.artworkRef.startsWith("placeholder:"))
            assertEquals(null, it.lastPlayedAtEpochMillis)
            assertEquals("", it.userNotes)
        }
    }
}
