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

    @Test fun containsRequestedGamesPlusOfficialAndroidEditions() {
        assertEquals(
            listOf(
                "EA Sports Cricket 07",
                "Grand Theft Auto III",
                "Grand Theft Auto: Vice City",
                "Grand Theft Auto: San Andreas",
                "Grand Theft Auto IV",
                "Grand Theft Auto V",
                "Grand Theft Auto III (Android)",
                "Grand Theft Auto: Vice City (Android)",
                "Grand Theft Auto: San Andreas (Android)",
            ),
            games.map { it.title },
        )
        assertEquals(1, games.count { it.category == GameCategory.CRICKET })
        assertEquals(8, games.count { it.category == GameCategory.GTA })
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

    @Test fun androidEditionsAreNativeUntestedAndLinkedToAPackage() {
        val android = games.filter { it.originalPlatform == GamePlatform.ANDROID }
        assertEquals(3, android.size)
        android.forEach {
            assertEquals(ExecutionType.ANDROID_NATIVE, it.executionType)
            assertEquals(CompatibilityStatus.NOT_TESTED, it.compatibilityStatus)
            assertEquals(InstallationStatus.NOT_INSTALLED, it.installationStatus)
            assertTrue(it.androidPackageName!!.startsWith("com.rockstargames."))
        }
        // There is no official Android release of GTA IV or GTA V.
        assertTrue(games.none { it.originalPlatform == GamePlatform.ANDROID && it.title.contains(Regex("IV|V\\b")) && !it.title.contains("Vice") })
    }

    @Test fun usesGeneratedPlaceholderArtworkAndNoUserData() {
        games.forEach {
            assertTrue(it.artworkRef.startsWith("placeholder:"))
            assertEquals(null, it.lastPlayedAtEpochMillis)
            assertEquals("", it.userNotes)
        }
    }
}
