package com.retroplay.app.launcher

import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.LaunchResult
import com.retroplay.app.domain.repository.UserPreferences
import com.retroplay.app.launcher.LauncherTestFixtures.compatApp
import com.retroplay.app.launcher.LauncherTestFixtures.pcGame
import com.retroplay.app.testutil.FakeAppStarter
import com.retroplay.app.testutil.FakePackageInspector
import com.retroplay.app.testutil.FakeUserPreferencesRepository
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ExternalEmulatorLauncherTest {

    @Test fun notConfiguredEvenWhenCompatibilityAppsAreInstalled() = runTest {
        // RetroPlay must not guess which installed app is the emulator.
        val starter = FakeAppStarter()
        val launcher = ExternalEmulatorLauncher(FakePackageInspector(compatApp), starter, FakeUserPreferencesRepository())

        val plan = launcher.plan(pcGame) as LaunchPlan.ExternalNotConfigured
        assertTrue(plan.steps.first().contains("your Windows compatibility app"))
        assertEquals(LaunchResult.NotStarted(plan), launcher.launch(pcGame))
        assertTrue(starter.started.isEmpty())
    }

    @Test fun configuredAppThatIsUninstalledIsReportedUnavailable() = runTest {
        val prefs = FakeUserPreferencesRepository(UserPreferences(externalAppPackage = compatApp.packageName, externalAppLabel = "Windows Runner"))
        val starter = FakeAppStarter()
        val launcher = ExternalEmulatorLauncher(FakePackageInspector(), starter, prefs)

        assertEquals("Windows Runner", (launcher.plan(pcGame) as LaunchPlan.ExternalAppMissing).configuredLabel)
        assertTrue(launcher.launch(pcGame) is LaunchResult.NotStarted)
        assertTrue(starter.started.isEmpty())
    }

    @Test fun configuredAppOpensWithManualStepsOnly() = runTest {
        val prefs = FakeUserPreferencesRepository(UserPreferences(externalAppPackage = compatApp.packageName, externalAppLabel = compatApp.label))
        val starter = FakeAppStarter()
        val launcher = ExternalEmulatorLauncher(FakePackageInspector(compatApp), starter, prefs)

        val plan = launcher.plan(pcGame) as LaunchPlan.ExternalReady
        assertEquals("Open Windows Runner.", plan.steps.first())
        assertTrue(plan.steps.any { "Grand Theft Auto: Vice City" in it })
        assertTrue(plan.note.contains("cannot start the game inside it"))

        assertEquals(LaunchResult.Started(compatApp, LaunchMethod.EXTERNAL_APP_OPENED), launcher.launch(pcGame))
        // Only the app's standard launcher entry is used: no extras, actions or file paths are passed.
        assertEquals(listOf(compatApp.packageName), starter.started)
    }
}
