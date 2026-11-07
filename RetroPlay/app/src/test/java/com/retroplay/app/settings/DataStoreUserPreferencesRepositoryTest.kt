package com.retroplay.app.settings

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class DataStoreUserPreferencesRepositoryTest {

    @get:Rule val tmp = TemporaryFolder()

    @Test fun defaultsAndPersistsComparisonPreference() = runTest {
        val file = File(tmp.root, "test.preferences_pb")
        val repo = DataStoreUserPreferencesRepository(
            PreferenceDataStoreFactory.create(scope = backgroundScope, produceFile = { file }),
        )
        assertTrue(repo.preferences.first().showReferenceComparison)

        repo.setShowReferenceComparison(false)
        assertFalse(repo.preferences.first().showReferenceComparison)
        assertTrue(file.exists())
    }

    @Test fun storesAndClearsExternalApp() = runTest {
        val repo = DataStoreUserPreferencesRepository(
            PreferenceDataStoreFactory.create(scope = backgroundScope, produceFile = { File(tmp.root, "ext.preferences_pb") }),
        )
        assertNull(repo.preferences.first().externalAppPackage)
        repo.setExternalApp("com.example.runner", "Runner")
        assertEquals("com.example.runner", repo.preferences.first().externalAppPackage)
        assertEquals("Runner", repo.preferences.first().externalAppLabel)
        repo.setExternalApp(null, null)
        assertNull(repo.preferences.first().externalAppPackage)
        assertNull(repo.preferences.first().externalAppLabel)
    }
}
