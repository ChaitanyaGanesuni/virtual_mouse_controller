package com.retroplay.app.di

import com.retroplay.app.core.time.Clock
import com.retroplay.app.storage.DocumentTreeReader
import com.retroplay.app.storage.PersistedFolderAccess
import com.retroplay.app.storage.SafDocumentTreeReader
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class StorageModule {
    @Binds abstract fun bindDocumentTreeReader(impl: SafDocumentTreeReader): DocumentTreeReader
    @Binds abstract fun bindPersistedFolderAccess(impl: SafDocumentTreeReader): PersistedFolderAccess

    companion object {
        @Provides fun provideClock(): Clock = Clock { System.currentTimeMillis() }
    }
}
