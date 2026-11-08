package com.retroplay.app.di

import android.content.Context
import androidx.room.Room
import com.retroplay.app.data.game.OfflineGameRepository
import com.retroplay.app.data.local.RetroPlayDatabase
import com.retroplay.app.data.local.dao.GameDao
import com.retroplay.app.data.local.dao.InstallationDao
import com.retroplay.app.data.game.OfflineInstallationRepository
import com.retroplay.app.domain.repository.InstallationRepository
import com.retroplay.app.domain.repository.GameRepository
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {
    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): RetroPlayDatabase =
        Room.databaseBuilder(context, RetroPlayDatabase::class.java, RetroPlayDatabase.NAME)
            .addMigrations(*RetroPlayDatabase.ALL_MIGRATIONS)
            .build()

    @Provides
    fun provideGameDao(database: RetroPlayDatabase): GameDao = database.gameDao()

    @Provides
    fun provideInstallationDao(database: RetroPlayDatabase): InstallationDao = database.installationDao()
}

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {
    @Binds
    abstract fun bindGameRepository(impl: OfflineGameRepository): GameRepository

    @Binds
    abstract fun bindInstallationRepository(impl: OfflineInstallationRepository): InstallationRepository
}
