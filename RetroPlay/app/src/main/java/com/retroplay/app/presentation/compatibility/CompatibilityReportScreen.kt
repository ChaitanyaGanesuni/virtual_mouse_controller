package com.retroplay.app.presentation.compatibility

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.retroplay.app.core.designsystem.component.CardHeader
import com.retroplay.app.core.designsystem.component.CompatibilityChip
import com.retroplay.app.core.designsystem.component.GameArtwork
import com.retroplay.app.core.designsystem.component.InfoRow
import com.retroplay.app.core.designsystem.component.RetroCard
import com.retroplay.app.core.designsystem.component.SectionLabel
import com.retroplay.app.domain.model.CompatibilityStatus
import com.retroplay.app.presentation.common.explanation

@Composable
fun CompatibilityReportScreen(
    onBack: () -> Unit,
    onOpenGame: (String) -> Unit,
    viewModel: CompatibilityReportViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    CompatibilityReportContent(state, onBack, onOpenGame)
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CompatibilityReportContent(
    state: CompatibilityReportUiState,
    onBack: () -> Unit,
    onOpenGame: (String) -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Compatibility report") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                RetroCard {
                    CardHeader("Test device", Icons.Filled.PhoneAndroid)
                    val d = state.device
                    InfoRow("Device", d?.model ?: "Reading…")
                    InfoRow("Android", d?.android ?: "Reading…")
                    InfoRow("GPU", d?.gpu ?: "Reading…")
                }
            }
            item {
                RetroCard {
                    CardHeader("Summary", Icons.Filled.Assessment)
                    Text(
                        "${state.testedCount} of ${state.games.size} games have a recorded test on this device.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Spacer(Modifier.height(12.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        state.statusCounts.forEach { (status, count) ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                CompatibilityChip(status)
                                Spacer(Modifier.width(4.dp))
                                Text("$count", style = MaterialTheme.typography.labelLarge)
                            }
                        }
                    }
                }
            }
            item { SectionLabel("Games") }
            items(state.games, key = { it.id }) { game ->
                RetroCard(onClick = { onOpenGame(game.id) }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        GameArtwork(game, Modifier.size(56.dp).clip(RoundedCornerShape(12.dp)), monogramSize = 18)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(game.title, style = MaterialTheme.typography.titleSmall)
                            Text(
                                game.executionType.label,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        CompatibilityChip(game.compatibilityStatus)
                    }
                }
            }
            item { SectionLabel("What the statuses mean") }
            item {
                RetroCard {
                    CompatibilityStatus.entries.forEachIndexed { i, status ->
                        if (i > 0) HorizontalDivider(Modifier.padding(vertical = 8.dp), color = MaterialTheme.colorScheme.outlineVariant)
                        CompatibilityChip(status)
                        Spacer(Modifier.height(4.dp))
                        Text(status.explanation, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "Playable and Working are only ever set from a real test on this device.",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                }
            }
        }
    }
}
