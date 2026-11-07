package com.retroplay.app.presentation.gamedetail

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.presentation.common.AppPickerDialog
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.retroplay.app.core.designsystem.component.CardHeader
import com.retroplay.app.core.designsystem.component.CompatibilityChip
import com.retroplay.app.core.designsystem.component.EmptyState
import com.retroplay.app.core.designsystem.component.GameArtwork
import com.retroplay.app.core.designsystem.component.InfoRow
import com.retroplay.app.core.designsystem.component.RetroCard
import com.retroplay.app.domain.model.Game
import com.retroplay.app.presentation.common.explanation
import java.text.DateFormat
import java.util.Date

@Composable
fun GameDetailScreen(onBack: () -> Unit, viewModel: GameDetailViewModel = hiltViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val picker by viewModel.picker.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    // Re-check installed apps whenever the user returns (e.g. from the Play Store).
    LifecycleResumeEffect(Unit) {
        viewModel.refresh()
        onPauseOrDispose {}
    }
    LaunchedEffect(message) {
        message?.let {
            snackbar.showSnackbar(it)
            viewModel.consumeMessage()
        }
    }

    Box {
        GameDetailContent(
            state = state,
            onBack = onBack,
            onFavoriteChange = viewModel::setFavorite,
            onSaveNotes = viewModel::saveNotes,
            launchActions = LaunchActions(
                onLaunch = viewModel::launch,
                onOpenStore = viewModel::openStoreListing,
                onLinkApp = { viewModel.showPicker(PickerPurpose.LINK_ANDROID_APP) },
                onChooseExternalApp = { viewModel.showPicker(PickerPurpose.CHOOSE_EXTERNAL_APP) },
            ),
        )
        SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).navigationBarsPadding())
    }
    picker?.let { (_, pickerState) ->
        AppPickerDialog(pickerState, onPick = viewModel::onAppPicked, onDismiss = viewModel::dismissPicker)
    }
}

@Composable
fun GameDetailContent(
    state: GameDetailUiState,
    onBack: () -> Unit,
    onFavoriteChange: (Boolean) -> Unit,
    onSaveNotes: (String) -> Unit,
    launchActions: LaunchActions = LaunchActions(),
) {
    // Surface (not a bare Box) so text inherits onBackground instead of the default black.
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { Box(Modifier.fillMaxSize()) {
        when (state) {
            GameDetailUiState.Loading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
            GameDetailUiState.NotFound -> EmptyState(
                "Game not found",
                "This entry is no longer in your library.",
                Modifier.align(Alignment.Center).padding(16.dp),
            )
            is GameDetailUiState.Ready -> GameDetailBody(state.game, state.launchPlan, launchActions, onFavoriteChange, onSaveNotes)
        }
        FilledIconButton(
            onClick = onBack,
            modifier = Modifier.statusBarsPadding().padding(8.dp),
            colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color.Black.copy(alpha = 0.5f)),
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Color.White)
        }
    }}
}

@Composable
private fun GameDetailBody(
    game: Game,
    launchPlan: LaunchPlan?,
    launchActions: LaunchActions,
    onFavoriteChange: (Boolean) -> Unit, onSaveNotes: (String) -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding(),
    ) {
        Box(Modifier.fillMaxWidth().height(300.dp)) {
            GameArtwork(game, Modifier.fillMaxSize(), monogramSize = 96)
            Box(
                Modifier
                    .fillMaxSize()
                    .background(Brush.verticalGradient(listOf(Color.Transparent, MaterialTheme.colorScheme.background))),
            )
            FilledIconButton(
                onClick = { onFavoriteChange(!game.isFavorite) },
                modifier = Modifier.align(Alignment.TopEnd).statusBarsPadding().padding(8.dp),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color.Black.copy(alpha = 0.5f)),
            ) {
                Icon(
                    if (game.isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                    contentDescription = if (game.isFavorite) "Remove from favourites" else "Add to favourites",
                    tint = if (game.isFavorite) MaterialTheme.colorScheme.primary else Color.White,
                )
            }
        }

        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(game.title, style = MaterialTheme.typography.headlineMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MetaPill(game.category.label)
                MetaPill(game.originalPlatform.label)
                game.releaseYear?.let { MetaPill(it.toString()) }
            }
            Text(game.description, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)

            LaunchCard(game, launchPlan, launchActions)

            RetroCard {
                CardHeader("Compatibility on this device", Icons.Filled.Verified)
                CompatibilityChip(game.compatibilityStatus)
                Spacer(Modifier.height(8.dp))
                Text(game.compatibilityStatus.explanation, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            RetroCard {
                CardHeader("Activity", Icons.Filled.Info)
                InfoRow(
                    "Last played",
                    game.lastPlayedAtEpochMillis?.let { DateFormat.getDateTimeInstance().format(Date(it)) } ?: "Never",
                )
                InfoRow("Favourite", if (game.isFavorite) "Yes" else "No")
            }

            NotesCard(game, onSaveNotes)
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun NotesCard(game: Game, onSaveNotes: (String) -> Unit) {
    var draft by rememberSaveable(game.id, game.userNotes) { mutableStateOf(game.userNotes) }
    RetroCard(Modifier.animateContentSize()) {
        CardHeader("Your notes", Icons.AutoMirrored.Filled.Notes)
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Setup steps, settings that worked, reminders…") },
            minLines = 3,
        )
        if (draft.trim() != game.userNotes) {
            Spacer(Modifier.height(8.dp))
            Button(onClick = { onSaveNotes(draft) }, modifier = Modifier.align(Alignment.End)) { Text("Save notes") }
        }
    }
}

@Composable
private fun MetaPill(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier
            .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(50))
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(50))
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}
