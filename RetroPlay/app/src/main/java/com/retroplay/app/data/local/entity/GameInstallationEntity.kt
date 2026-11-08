package com.retroplay.app.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.PrimaryKey
import com.retroplay.app.domain.model.GameInstallation
import com.retroplay.app.domain.model.ImportValidity

/** One imported file set per game. Only references are stored; files stay where the user keeps them. */
@Entity(
    tableName = "game_installations",
    foreignKeys = [
        ForeignKey(
            entity = GameEntity::class,
            parentColumns = ["id"],
            childColumns = ["gameId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
)
data class GameInstallationEntity(
    @PrimaryKey val gameId: String,
    val folderUri: String,
    val folderDisplayPath: String,
    val executableRelativePath: String,
    val executableSizeBytes: Long,
    val importedAt: Long,
    val lastValidatedAt: Long,
    val validity: ImportValidity,
    val message: String?,
) {
    fun toDomain() = GameInstallation(
        gameId, folderUri, folderDisplayPath, executableRelativePath, executableSizeBytes,
        importedAt, lastValidatedAt, validity, message,
    )

    companion object {
        fun fromDomain(i: GameInstallation) = GameInstallationEntity(
            i.gameId, i.folderUri, i.folderDisplayPath, i.executableRelativePath, i.executableSizeBytes,
            i.importedAtEpochMillis, i.lastValidatedAtEpochMillis, i.validity, i.message,
        )
    }
}
