package com.retroplay.app.data.game

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.retroplay.app.data.local.RetroPlayDatabase
import com.retroplay.app.domain.game.GameCatalogue
import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.model.InstallationStatus
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Exercises the real Room database (in-memory) through the repository. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class OfflineGameRepositoryTest {

    private lateinit var db: RetroPlayDatabase
    private lateinit var repository: OfflineGameRepository

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, RetroPlayDatabase::class.java).allowMainThreadQueries().build()
        repository = OfflineGameRepository(db.gameDao())
    }

    @After fun tearDown() = db.close()

    @Test fun seedsCatalogueInCatalogueOrder() = runTest {
        val games = repository.observeGames().first()
        assertEquals(GameCatalogue.initialGames.map { it.id }, games.map { it.id })
        assertEquals(GameCatalogue.initialGames, games)
    }

    @Test fun favouritesAreStoredAndRemoved() = runTest {
        repository.observeGames().first()
        repository.setFavorite("gta-vice-city", true)
        assertTrue(repository.observeGame("gta-vice-city").first()!!.isFavorite)
        assertEquals(listOf("gta-vice-city"), repository.observeGames().first().filter { it.isFavorite }.map { it.id })

        repository.setFavorite("gta-vice-city", false)
        assertFalse(repository.observeGame("gta-vice-city").first()!!.isFavorite)
    }

    @Test fun notesAreTrimmedAndSurviveReseeding() = runTest {
        repository.observeGames().first()
        repository.updateNotes("gta-iii", "  Use VirGL first  ")

        // A fresh repository instance re-runs seeding; existing rows must not be overwritten.
        val reopened = OfflineGameRepository(db.gameDao())
        assertEquals("Use VirGL first", reopened.observeGame("gta-iii").first()!!.userNotes)
    }

    @Test fun androidLaunchUpdatesLastPlayedButOpeningAnExternalAppDoesNot() = runTest {
        repository.observeGames().first()
        repository.recordLaunch("gta-iii", LaunchMethod.EXTERNAL_APP_OPENED, 1_000)
        assertNull(repository.observeGame("gta-iii").first()!!.lastPlayedAtEpochMillis)

        repository.recordLaunch("gta-iii-android", LaunchMethod.ANDROID_APP, 2_000)
        assertEquals(2_000L, repository.observeGame("gta-iii-android").first()!!.lastPlayedAtEpochMillis)
        assertEquals(1, db.gameDao().playHistory("gta-iii").size)
        assertEquals(1, db.gameDao().playHistory("gta-iii-android").size)
    }

    @Test fun linksAndroidPackageAndInstallationStatus() = runTest {
        repository.observeGames().first()
        repository.setAndroidPackage("gta-iii-android", " com.example.edition ")
        repository.updateInstallationStatus("gta-iii-android", InstallationStatus.INSTALLED)
        val game = repository.observeGame("gta-iii-android").first()!!
        assertEquals("com.example.edition", game.androidPackageName)
        assertEquals(InstallationStatus.INSTALLED, game.installationStatus)
    }

    @Test fun unknownGameIsNull() = runTest {
        assertNull(repository.observeGame("does-not-exist").first())
    }
}
