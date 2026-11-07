package com.retroplay.app.di

import com.retroplay.app.domain.launch.GameLaunchManager
import com.retroplay.app.launcher.AndroidAppStarter
import com.retroplay.app.launcher.AndroidPackageInspector
import com.retroplay.app.launcher.AppStarter
import com.retroplay.app.launcher.DefaultGameLaunchManager
import com.retroplay.app.launcher.PackageInspector
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class LauncherModule {
    @Binds abstract fun bindPackageInspector(impl: AndroidPackageInspector): PackageInspector
    @Binds abstract fun bindAppStarter(impl: AndroidAppStarter): AppStarter
    @Binds abstract fun bindGameLaunchManager(impl: DefaultGameLaunchManager): GameLaunchManager
}
