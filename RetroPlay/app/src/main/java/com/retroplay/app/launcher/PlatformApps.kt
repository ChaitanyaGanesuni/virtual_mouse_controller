package com.retroplay.app.launcher

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import com.retroplay.app.domain.launch.InstalledApp
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/** Read-only view of installed apps. Visibility is limited to what the manifest's <queries> declare. */
interface PackageInspector {
    /** Returns the app if it is installed and has a launcher activity; null otherwise. */
    fun launchableApp(packageName: String): InstalledApp?
    fun launchableApps(): List<InstalledApp>
}

/** Starts other apps. Every call is user-initiated; nothing is installed. */
interface AppStarter {
    fun startApp(packageName: String): Result<Unit>
    fun openStoreListing(packageName: String): Boolean
}

@Singleton
class AndroidPackageInspector @Inject constructor(
    @ApplicationContext private val context: Context,
) : PackageInspector {
    private val pm: PackageManager get() = context.packageManager

    override fun launchableApp(packageName: String): InstalledApp? {
        if (pm.getLaunchIntentForPackage(packageName) == null) return null
        return try {
            val info = pm.getApplicationInfo(packageName, 0)
            InstalledApp(packageName, pm.getApplicationLabel(info).toString())
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    override fun launchableApps(): List<InstalledApp> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .map { InstalledApp(it.activityInfo.packageName, it.loadLabel(pm).toString()) }
            .filter { it.packageName != context.packageName }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
    }
}

@Singleton
class AndroidAppStarter @Inject constructor(
    @ApplicationContext private val context: Context,
) : AppStarter {

    override fun startApp(packageName: String): Result<Unit> {
        val intent = context.packageManager.getLaunchIntentForPackage(packageName)
            ?: return Result.failure(IllegalStateException("The app is not installed or has no launcher screen."))
        return try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            Result.success(Unit)
        } catch (e: ActivityNotFoundException) {
            Result.failure(e)
        } catch (e: SecurityException) {
            Result.failure(e)
        }
    }

    override fun openStoreListing(packageName: String): Boolean {
        val uris = listOf(
            "market://details?id=$packageName",
            "https://play.google.com/store/apps/details?id=$packageName",
        )
        for (uri in uris) {
            try {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next option.
            }
        }
        return false
    }
}
