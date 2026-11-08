package com.retroplay.app.launcher

import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.LaunchResult
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.InstallationStatus
import com.retroplay.app.domain.repository.UserPreferences
import com.retroplay.app.launcher.LauncherTestFixtures.androidGame
import com.retroplay.app.launcher.LauncherTestFixtures.androidGameApp
import com.retroplay.app.launcher.LauncherTestFixtures.compatApp
import com.retroplay.app.launcher.LauncherTestFixtures.pcGame
import com.retroplay.app.testutil.FakeAppStarter
import com.retroplay.app.testutil.FakeGameRepository
import com.retroplay.app.testutil.FakeInstallationRepository
import com.retroplay.app.testutil.FakePackageInspector
import com.retroplay.app.testutil.FakeUserPreferencesRepository
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultGameLaunchManagerTest {

    private class Env(scope: TestScope, vararg installed: com.retroplay.app.domain.launch.InstalledApp, prefs: UserPreferences = UserPreferences()) {
        val inspector = FakePackageInspector(*installed)
        val starter = FakeAppStarter()
        val repo = FakeGameRepository()
        val prefsRepo = FakeUserPreferencesRepository(prefs)
        val manager = DefaultGameLaunchManager(
            AndroidGameLauncher(inspector, starter),
            ExternalEmulatorLauncher(inspector, starter, prefsRepo, FakeInstallationRepository()),
            UnsupportedGameHandler(),
            inspector,
            starter,
            repo,
            StandardTestDispatcher(scope.testScheduler),
        )
        suspend fun stored(id: String) = repo.observeGame(id).first()!!
    }

    @Test fun androidLaunchRecordsHistoryAndLastPlayed() = runTest {
        val env = Env(this, androidGameApp)
        val result = env.manager.launch(androidGame)
        assertEquals(LaunchMethod.ANDROID_APP, (result as LaunchResult.Started).method)
        assertEquals(androidGame.id, env.repo.launches.single().first)
        assertTrue(env.stored(androidGame.id).lastPlayedAtEpochMillis != null)
    }

    @Test fun openingCompatibilityAppIsLoggedButIsNotPlaying() = runTest {
        val env = Env(this, compatApp, prefs = UserPreferences(externalAppPackage = compatApp.packageName, externalAppLabel = compatApp.label))
        env.manager.launch(pcGame)
        assertEquals(LaunchMethod.EXTERNAL_APP_OPENED, env.repo.launches.single().second)
        assertNull(env.stored(pcGame.id).lastPlayedAtEpochMillis)
    }

    @Test fun notStartedLaunchRecordsNothing() = runTest {
        val env = Env(this)
        assertTrue(env.manager.launch(pcGame) is LaunchResult.NotStarted)
        assertTrue(env.manager.launch(androidGame) is LaunchResult.NotStarted)
        assertTrue(env.repo.launches.isEmpty())
        assertTrue(env.starter.started.isEmpty())
    }

    @Test fun unsupportedTakesPriorityOverInstalledApp() = runTest {
        val env = Env(this, androidGameApp)
        val game = androidGame.copy(compatibilityStatus = CompatibilityStatus.UNSUPPORTED)
        assertTrue(env.manager.plan(game) is LaunchPlan.Unsupported)
        assertTrue(env.manager.launch(game) is LaunchResult.NotStarted)
        assertTrue(env.starter.started.isEmpty())
    }

    @Test fun installationStatusFollowsInstalledApps() = runTest {
        val env = Env(this, androidGameApp)
        env.manager.plan(androidGame)
        assertEquals(InstallationStatus.INSTALLED, env.stored(androidGame.id).installationStatus)

        env.inspector.installed.clear()
        env.manager.plan(env.stored(androidGame.id))
        assertEquals(InstallationStatus.MISSING, env.stored(androidGame.id).installationStatus)
        env.manager.plan(env.stored(androidGame.id))
        assertEquals(InstallationStatus.MISSING, env.stored(androidGame.id).installationStatus)
    }

    @Test fun storeListingIsOnlyOpenedOnRequest() = runTest {
        val env = Env(this)
        env.manager.plan(androidGame)
        assertTrue(env.starter.storeOpened.isEmpty())
        assertTrue(env.manager.openStoreListing("com.rockstargames.gtasa"))
        assertEquals(listOf("com.rockstargames.gtasa"), env.starter.storeOpened)
    }
}
