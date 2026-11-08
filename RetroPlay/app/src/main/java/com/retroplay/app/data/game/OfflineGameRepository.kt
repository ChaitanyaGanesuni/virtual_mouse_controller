package com.retroplay.app.data.game

import com.retroplay.app.data.local.dao.GameDao
import com.retroplay.app.data.local.entity.FavoriteEntity
import com.retroplay.app.data.local.entity.GameEntity
import com.retroplay.app.data.local.entity.PlayHistoryEntity
import com.retroplay.app.domain.launch.LaunchMethod
import com.retroplay.app.domain.model.InstallationStatus
import com.retroplay.app.domain.game.GameCatalogue
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.repository.GameRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.ExecutionType
import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.model.GamePlatform
import java.util.UUID
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

    override suspend fun setAndroidPackage(id: String, packageName: String?) {
        gameDao.updateAndroidPackage(id, packageName?.trim()?.ifEmpty { null })
    }

    override suspend fun updateInstallationStatus(id: String, status: InstallationStatus) {
        gameDao.updateInstallationStatus(id, status)
    }

    override suspend fun recordLaunch(id: String, method: LaunchMethod, atEpochMillis: Long) {
        gameDao.insertPlayHistory(PlayHistoryEntity(gameId = id, launchedAt = atEpochMillis, method = method))
        // Opening an external compatibility app does not prove the game itself was played.
        if (method == LaunchMethod.ANDROID_APP) gameDao.updateLastPlayed(id, atEpochMillis)
    }

    override suspend fun registerCustomGame(title: String, category: GameCategory): Game {
        val clean = title.trim()
        require(clean.isNotEmpty()) { "Title must not be empty" }
        val id = Game.CUSTOM_ID_PREFIX + UUID.randomUUID().toString()
        val game = Game(
            id = id,
            title = clean,
            shortTitle = monogram(clean),
            category = category,
            originalPlatform = GamePlatform.WINDOWS_PC,
            releaseYear = null,
            description = "Added by you. Import your legally obtained game files to register them with RetroPlay.",
            artworkRef = "placeholder:$id",
            executionType = ExecutionType.EXTERNAL_EMULATOR,
            installationStatus = InstallationStatus.NOT_IMPORTED,
            compatibilityStatus = CompatibilityStatus.NOT_TESTED,
            lastPlayedAtEpochMillis = null,
            userNotes = "",
            isFavorite = false,
            sortOrder = CUSTOM_SORT_ORDER,
        )
        gameDao.insertGame(GameEntity.fromDomain(game))
        return game
    }

    override suspend fun removeCustomGame(id: String): Boolean {
        if (!id.startsWith(Game.CUSTOM_ID_PREFIX)) return false
        return gameDao.deleteGame(id) > 0
    }

    private suspend fun ensureCatalogueSeeded() = seedLock.withLock {
        if (!seeded) {
            gameDao.insertIfAbsent(GameCatalogue.initialGames.map(GameEntity::fromDomain))
            seeded = true
        }
    }

    private companion object {
        const val CUSTOM_SORT_ORDER = 1_000

        /** "Need for Speed Underground" -> "NSU"; single words use their first two letters. */
        fun monogram(title: String): String {
            val words = title.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
            val letters = if (words.size >= 2) words.take(3).joinToString("") { it.first().toString() } else title.take(2)
            return letters.uppercase()
        }
    }
}
