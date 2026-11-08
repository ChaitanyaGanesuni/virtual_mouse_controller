package com.retroplay.app.data.local

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Verifies v1 → v2 against the exported schemas, keeping user data. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class MigrationTest {

    @get:Rule
    val helper = MigrationTestHelper(InstrumentationRegistry.getInstrumentation(), RetroPlayDatabase::class.java)

    @Test fun migrate1To2KeepsNotesAndFavourites() {
        helper.createDatabase(DB, 1).apply {
            execSQL(
                "INSERT INTO games (id, title, shortTitle, category, originalPlatform, releaseYear, description, " +
                    "artworkRef, executionType, installationStatus, compatibilityStatus, lastPlayedAt, userNotes, sortOrder) " +
                    "VALUES ('gta-iii', 'Grand Theft Auto III', 'III', 'GTA', 'WINDOWS_PC', 2002, 'd', 'placeholder:gta-iii', " +
                    "'EXTERNAL_EMULATOR', 'NOT_IMPORTED', 'NOT_TESTED', NULL, 'my notes', 10)",
            )
            execSQL("INSERT INTO favorites (gameId, addedAt) VALUES ('gta-iii', 1)")
            close()
        }

        val db = helper.runMigrationsAndValidate(DB, 2, true, *RetroPlayDatabase.ALL_MIGRATIONS)

        db.query("SELECT userNotes, androidPackageName FROM games WHERE id = 'gta-iii'").use {
            assertTrue(it.moveToFirst())
            assertEquals("my notes", it.getString(0))
            assertTrue(it.isNull(1))
        }
        db.query("SELECT COUNT(*) FROM favorites").use { it.moveToFirst(); assertEquals(1, it.getInt(0)) }
        db.query("SELECT COUNT(*) FROM play_history").use { it.moveToFirst(); assertEquals(0, it.getInt(0)) }
    }

    @Test fun migrate2To3AddsInstallationsTable() {
        helper.createDatabase(DB, 2).close()
        val db = helper.runMigrationsAndValidate(DB, 3, true, *RetroPlayDatabase.ALL_MIGRATIONS)
        db.query("SELECT COUNT(*) FROM game_installations").use { it.moveToFirst(); assertEquals(0, it.getInt(0)) }
    }

    @Test fun migrate1To3InOneGo() {
        helper.createDatabase(DB, 1).close()
        helper.runMigrationsAndValidate(DB, 3, true, *RetroPlayDatabase.ALL_MIGRATIONS)
    }

    private companion object {
        const val DB = "migration-test"
    }
}
