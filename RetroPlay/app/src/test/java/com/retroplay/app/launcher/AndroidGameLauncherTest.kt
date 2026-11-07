package com.retroplay.app.launcher

import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.LaunchResult
import com.retroplay.app.launcher.LauncherTestFixtures.androidGame
import com.retroplay.app.launcher.LauncherTestFixtures.androidGameApp
import com.retroplay.app.testutil.FakeAppStarter
import com.retroplay.app.testutil.FakePackageInspector
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidGameLauncherTest {

    @Test fun installedGameIsReadyAndLaunches() {
        val starter = FakeAppStarter()
        val launcher = AndroidGameLauncher(FakePackageInspector(androidGameApp), starter)

        assertEquals(LaunchPlan.AndroidReady(androidGameApp), launcher.plan(androidGame))
        assertEquals(LaunchResult.Started(androidGameApp, LaunchMethod.ANDROID_APP), launcher.launch(androidGame))
        assertEquals(listOf("com.rockstargames.gtasa"), starter.started)
    }

    @Test fun missingGameGivesGuidanceAndNeverStartsAnything() {
        val starter = FakeAppStarter()
        val launcher = AndroidGameLauncher(FakePackageInspector(), starter)

        val plan = launcher.plan(androidGame) as LaunchPlan.AndroidNotInstalled
        assertEquals("com.rockstargames.gtasa", plan.expectedPackage)
        assertTrue(plan.guidance.any { "never installs" in it })
        assertEquals(LaunchResult.NotStarted(plan), launcher.launch(androidGame))
        assertTrue(starter.started.isEmpty())
    }

    @Test fun unlinkedGameHasNoStorePackage() {
        val plan = AndroidGameLauncher(FakePackageInspector(), FakeAppStarter())
            .plan(androidGame.copy(androidPackageName = null)) as LaunchPlan.AndroidNotInstalled
        assertEquals(null, plan.expectedPackage)
    }

    @Test fun startFailureIsReported() {
        val launcher = AndroidGameLauncher(FakePackageInspector(androidGameApp), FakeAppStarter(failWith = SecurityException("denied")))
        val result = launcher.launch(androidGame) as LaunchResult.Failed
        assertTrue(result.message.contains("denied"))
    }
}
