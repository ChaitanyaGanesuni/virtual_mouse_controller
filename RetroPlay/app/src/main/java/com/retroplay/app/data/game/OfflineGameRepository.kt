package com.retroplay.app.data.game

import com.retroplay.app.data.local.dao.GameDao
import com.retroplay.app.data.local.entity.FavoriteEntity
import com.retroplay.app.data.local.entity.GameEntity
import com.retroplay.app.domain.game.GameCatalogue
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.repository.GameRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton

/** Room-backed [GameRepository]. Seeds the metadata catalogue once per process, never overwriting user data. */
@Singleton
class OfflineGameRepository @Inject constructor(
    private val gameDao: GameDao,
) : GameRepository {

    private val seedLock = Mutex()
    private var seeded = false

    override fun observeGames(): Flow<List<Game>> = gameDao.observeGames()
        .onStart { ensureCatalogueSeeded() }
        .map { rows -> rows.map { it.game.toDomain(it.isFavorite) } }

    override fun observeGame(id: String): Flow<Game?> = gameDao.observeGame(id)
        .onStart { ensureCatalogueSeeded() }
        .map { row -> row?.game?.toDomain(row.isFavorite) }

    override suspend fun setFavorite(id: String, favorite: Boolean) {
        if (favorite) gameDao.addFavorite(FavoriteEntity(id, System.currentTimeMillis()))
        else gameDao.removeFavorite(id)
    }

    override suspend fun updateNotes(id: String, notes: String) {
        gameDao.updateNotes(id, notes.trim())
    }

    private suspend fun ensureCatalogueSeeded() = seedLock.withLock {
        if (!seeded) {
            gameDao.insertIfAbsent(GameCatalogue.initialGames.map(GameEntity::fromDomain))
            seeded = true
        }
    }
}
