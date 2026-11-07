package com.retroplay.app.core.designsystem.component

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.domain.model.Game
import com.retroplay.app.presentation.common.color
import com.retroplay.app.presentation.common.icon
import kotlin.math.abs

private val ArtworkPalettes = listOf(
    Color(0xFF6D28D9) to Color(0xFF0EA5E9),
    Color(0xFF7C3AED) to Color(0xFF1E3A8A),
    Color(0xFF0369A1) to Color(0xFF9333EA),
    Color(0xFF4C1D95) to Color(0xFF22B8FF),
    Color(0xFF1D4ED8) to Color(0xFF7E22CE),
    Color(0xFF581C87) to Color(0xFF0284C7),
)

/**
 * Game artwork. Shows a licensed image when the user supplies one (content://, file:// or https://);
 * otherwise draws original generated placeholder art: a gradient, the category icon and a monogram.
 */
@Composable
fun GameArtwork(game: Game, modifier: Modifier = Modifier, monogramSize: Int = 44) {
    val isImage = game.artworkRef.startsWith("content://") ||
        game.artworkRef.startsWith("file://") ||
        game.artworkRef.startsWith("https://")
    if (isImage) {
        AsyncImage(
            model = game.artworkRef,
            contentDescription = game.title,
            contentScale = ContentScale.Crop,
            modifier = modifier,
        )
        return
    }
    val (start, end) = ArtworkPalettes[abs(game.id.hashCode()) % ArtworkPalettes.size]
    Box(
        modifier = modifier.background(Brush.linearGradient(listOf(start, Color(0xFF0B0B10), end))),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            game.category.icon,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.10f),
            modifier = Modifier.fillMaxSize(0.8f),
        )
        Text(
            game.shortTitle,
            color = Color.White,
            fontSize = monogramSize.sp,
            fontWeight = FontWeight.Black,
        )
    }
}

@Composable
fun CompatibilityChip(status: CompatibilityStatus, modifier: Modifier = Modifier) {
    val color = status.color
    Row(
        modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.15f))
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(6.dp).clip(RoundedCornerShape(50)).background(color))
        Spacer(Modifier.width(6.dp))
        Text(status.label, style = MaterialTheme.typography.labelSmall, color = color)
    }
}

/** Poster-style game card for grids and carousels. */
@Composable
fun GameCard(game: Game, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Surface(
        onClick = onClick,
        modifier = modifier,
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
    ) {
        Column {
            Box {
                GameArtwork(
                    game,
                    Modifier
                        .fillMaxWidth()
                        .aspectRatio(3f / 4f)
                        .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)),
                )
                if (game.isFavorite) {
                    Icon(
                        Icons.Filled.Favorite,
                        contentDescription = "Favourite",
                        tint = Color.White,
                        modifier = Modifier.align(Alignment.TopEnd).padding(10.dp).size(18.dp),
                    )
                }
            }
            Column(Modifier.padding(12.dp)) {
                Text(
                    game.title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.height(40.dp),
                )
                Text(
                    listOfNotNull(game.originalPlatform.label, game.releaseYear?.toString()).joinToString(" · "),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(8.dp))
                CompatibilityChip(game.compatibilityStatus)
            }
        }
    }
}

@Composable
fun EmptyState(title: String, message: String, modifier: Modifier = Modifier) {
    RetroCard(modifier) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(4.dp))
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
