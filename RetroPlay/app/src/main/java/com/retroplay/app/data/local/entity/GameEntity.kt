package com.retroplay.app.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.ExecutionType
import com.retroplay.app.domain.model.Game
import com.retroplay.app.domain.model.GameCategory
import com.retroplay.app.domain.model.GamePlatform
import com.retroplay.app.domain.model.InstallationStatus

@Entity(tableName = "games")
data class GameEntity(
    @PrimaryKey val id: String,
    val title: String,
    val shortTitle: String,
    val category: GameCategory,
    val originalPlatform: GamePlatform,
    val releaseYear: Int?,
    val description: String,
    val artworkRef: String,
    val executionType: ExecutionType,
    val installationStatus: InstallationStatus,
    val compatibilityStatus: CompatibilityStatus,
    val lastPlayedAt: Long?,
    val userNotes: String,
    val sortOrder: Int,
) {
    fun toDomain(isFavorite: Boolean) = Game(
        id = id,
        title = title,
        shortTitle = shortTitle,
        category = category,
        originalPlatform = originalPlatform,
        releaseYear = releaseYear,
        description = description,
        artworkRef = artworkRef,
        executionType = executionType,
        installationStatus = installationStatus,
        compatibilityStatus = compatibilityStatus,
        lastPlayedAtEpochMillis = lastPlayedAt,
        userNotes = userNotes,
        isFavorite = isFavorite,
        sortOrder = sortOrder,
    )

    companion object {
        fun fromDomain(game: Game) = GameEntity(
            id = game.id,
            title = game.title,
            shortTitle = game.shortTitle,
            category = game.category,
            originalPlatform = game.originalPlatform,
            releaseYear = game.releaseYear,
            description = game.description,
            artworkRef = game.artworkRef,
            executionType = game.executionType,
            installationStatus = game.installationStatus,
            compatibilityStatus = game.compatibilityStatus,
            lastPlayedAt = game.lastPlayedAtEpochMillis,
            userNotes = game.userNotes,
            sortOrder = game.sortOrder,
        )
    }
}
