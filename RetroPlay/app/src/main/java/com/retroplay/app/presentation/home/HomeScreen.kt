package com.retroplay.app.presentation.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.retroplay.app.R
import com.retroplay.app.core.designsystem.component.CardHeader
import com.retroplay.app.core.designsystem.component.EmptyState
import com.retroplay.app.core.designsystem.component.GameCard
import com.retroplay.app.core.designsystem.component.RetroCard
import com.retroplay.app.core.designsystem.component.SectionLabel
import com.retroplay.app.core.designsystem.theme.RetroGradients
import com.retroplay.app.domain.model.Game
import com.retroplay.app.presentation.common.icon

@Composable
fun HomeScreen(
    onOpenGame: (String) -> Unit,
    onOpenLibrary: () -> Unit,
    onOpenDeviceInfo: () -> Unit,
    viewModel: HomeViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    HomeContent(state, onOpenGame, onOpenLibrary, onOpenDeviceInfo)
}

@Composable
fun HomeContent(
    state: HomeUiState,
    onOpenGame: (String) -> Unit,
    onOpenLibrary: () -> Unit,
    onOpenDeviceInfo: () -> Unit,
) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding(),
        contentPadding = PaddingValues(vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Hero(state, Modifier.padding(horizontal = 16.dp)) }

        item { SectionHeader("Continue playing") }
        item {
            if (state.recentlyPlayed.isEmpty()) {
                EmptyState(
                    "Nothing played yet",
                    "Games you launch from RetroPlay will appear here.",
                    Modifier.padding(horizontal = 16.dp),
                )
            } else {
                GameRow(state.recentlyPlayed, onOpenGame)
            }
        }

        if (state.favorites.isNotEmpty()) {
            item { SectionHeader("Favourites") }
            item { GameRow(state.favorites, onOpenGame) }
        }

        item { SectionHeader("Your library", actionLabel = "See all", onAction = onOpenLibrary) }
        item { GameRow(state.library, onOpenGame) }

        item { SectionHeader("Your device") }
        item {
            RetroCard(Modifier.padding(horizontal = 16.dp), onClick = onOpenDeviceInfo) {
                CardHeader(stringResource(R.string.title_device_info), Icons.Filled.PhoneAndroid)
                Text(
                    "See the hardware profile measured on this phone and how it compares with the Pixel 9 reference.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    } }
}

@Composable
private fun Hero(state: HomeUiState, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.extraLarge)
            .background(RetroGradients.Hero)
            .padding(24.dp),
    ) {
        Column {
            Icon(Icons.Filled.SportsEsports, contentDescription = null, tint = Color.White)
            Spacer(Modifier.height(12.dp))
            Text(stringResource(R.string.app_name), style = MaterialTheme.typography.displaySmall, color = Color.White)
            Text(stringResource(R.string.app_tagline), style = MaterialTheme.typography.titleMedium, color = Color.White.copy(alpha = 0.85f))
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                state.categoryCounts.forEach { (category, count) ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(category.icon, contentDescription = null, tint = Color.White.copy(alpha = 0.85f))
                        Spacer(Modifier.width(6.dp))
                        Text("$count ${category.label}", style = MaterialTheme.typography.labelLarge, color = Color.White)
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String, actionLabel: String? = null, onAction: () -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SectionLabel(title, Modifier.weight(1f))
        if (actionLabel != null) TextButton(onClick = onAction) { Text(actionLabel) }
    }
}

@Composable
private fun GameRow(games: List<Game>, onOpenGame: (String) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(games, key = { it.id }) { game ->
            GameCard(game, onClick = { onOpenGame(game.id) }, modifier = Modifier.width(156.dp).animateItem())
        }
    }
}
