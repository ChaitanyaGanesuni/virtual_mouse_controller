package com.retroplay.app.data.game

import com.retroplay.app.data.local.dao.InstallationDao
import com.retroplay.app.data.local.entity.GameInstallationEntity
import com.retroplay.app.domain.model.GameInstallation
import com.retroplay.app.domain.repository.InstallationRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OfflineInstallationRepository @Inject constructor(
    private val dao: InstallationDao,
) : InstallationRepository {
    override fun observe(gameId: String): Flow<GameInstallation?> = dao.observe(gameId).map { it?.toDomain() }
    override suspend fun get(gameId: String): GameInstallation? = dao.get(gameId)?.toDomain()
    override suspend fun upsert(installation: GameInstallation) = dao.upsert(GameInstallationEntity.fromDomain(installation))
    override suspend fun delete(gameId: String) = dao.delete(gameId)
    override suspend fun countUsingFolder(folderUri: String): Int = dao.countUsingFolder(folderUri)
}
