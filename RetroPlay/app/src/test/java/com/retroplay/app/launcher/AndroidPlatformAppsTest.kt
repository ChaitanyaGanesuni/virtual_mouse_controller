package com.retroplay.app.launcher

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Runs the real PackageManager-based code against Robolectric's simulated package manager. */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class AndroidPlatformAppsTest {

    private lateinit var context: Context

    @Before fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    private fun installLaunchable(pkg: String, label: String) {
        val spm = shadowOf(context.packageManager)
        spm.installPackage(
            PackageInfo().apply {
                packageName = pkg
                applicationInfo = ApplicationInfo().apply { packageName = pkg; nonLocalizedLabel = label }
            },
        )
        val component = ComponentName(pkg, "$pkg.MainActivity")
        spm.addActivityIfNotPresent(component)
        spm.addIntentFilterForActivity(
            component,
            IntentFilter(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) },
        )
    }

    @Test fun findsInstalledLaunchableGame() {
        installLaunchable("com.rockstargames.gtasa", "GTA: San Andreas")
        val app = AndroidPackageInspector(context).launchableApp("com.rockstargames.gtasa")
        assertEquals("com.rockstargames.gtasa", app?.packageName)
        assertEquals("GTA: San Andreas", app?.label)
    }

    @Test fun missingGameIsNull() {
        assertNull(AndroidPackageInspector(context).launchableApp("com.rockstargames.gtavc"))
    }

    @Test fun listsLaunchableAppsSortedByLabel() {
        installLaunchable("com.example.b", "Bravo")
        installLaunchable("com.example.a", "alpha")
        val apps = AndroidPackageInspector(context).launchableApps().map { it.label }
        assertEquals(listOf("alpha", "Bravo"), apps.filter { it in setOf("alpha", "Bravo") })
        assertFalse(AndroidPackageInspector(context).launchableApps().any { it.packageName == context.packageName })
    }

    @Test fun startAppUsesStandardLauncherIntent() {
        installLaunchable("com.example.runner", "Runner")
        assertTrue(AndroidAppStarter(context).startApp("com.example.runner").isSuccess)
        val started = shadowOf(ApplicationProvider.getApplicationContext<android.app.Application>()).nextStartedActivity
        assertEquals("com.example.runner", started.component?.packageName ?: started.`package`)
        assertTrue(started.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        assertNull(started.data)
    }

    @Test fun startingMissingAppFailsWithoutCrashing() {
        assertTrue(AndroidAppStarter(context).startApp("com.example.notinstalled").isFailure)
    }
}
