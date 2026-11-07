package com.retroplay.app.presentation.gamedetail

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.retroplay.app.core.designsystem.component.CardHeader
import com.retroplay.app.core.designsystem.component.InfoRow
import com.retroplay.app.core.designsystem.component.RetroCard
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.model.Game
import com.retroplay.app.presentation.common.explanation

data class LaunchActions(
    val onLaunch: () -> Unit = {},
    val onOpenStore: (String) -> Unit = {},
    val onLinkApp: () -> Unit = {},
    val onChooseExternalApp: () -> Unit = {},
)

/** Shows exactly what RetroPlay can do for this game. Buttons only appear for actions that really happen. */
@Composable
fun LaunchCard(game: Game, plan: LaunchPlan?, actions: LaunchActions) {
    RetroCard {
        CardHeader(
            if (plan is LaunchPlan.Unsupported) "Cannot launch" else "Launch",
            if (plan is LaunchPlan.Unsupported) Icons.Filled.Block else Icons.Filled.PlayCircle,
        )
        InfoRow("Execution", game.executionType.label)
        InfoRow("Installation", game.installationStatus.label)
        Spacer(Modifier.height(8.dp))
        when (plan) {
            null -> Muted("Checking what's installed…")
            is LaunchPlan.AndroidReady -> {
                Muted("Installed: ${plan.app.label} (${plan.app.packageName})")
                Spacer(Modifier.height(12.dp))
                Button(onClick = actions.onLaunch, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Play")
                }
                TextButton(onClick = actions.onLinkApp) { Text("Link a different app") }
            }
            is LaunchPlan.AndroidNotInstalled -> {
                Bullets(plan.guidance)
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    plan.expectedPackage?.let { pkg ->
                        OutlinedButton(onClick = { actions.onOpenStore(pkg) }) {
                            Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
                            Spacer(Modifier.width(6.dp))
                            Text("Store listing")
                        }
                    }
                    OutlinedButton(onClick = actions.onLinkApp) { Text("Link installed app") }
                }
            }
            is LaunchPlan.ExternalReady -> {
                Steps(plan.steps)
                Spacer(Modifier.height(12.dp))
                Button(onClick = actions.onLaunch, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Open ${plan.app.label}")
                }
                TextButton(onClick = actions.onChooseExternalApp) { Text("Use a different compatibility app") }
                Muted(plan.note)
            }
            is LaunchPlan.ExternalNotConfigured -> {
                Muted(game.executionType.explanation)
                Spacer(Modifier.height(8.dp))
                Steps(plan.steps)
                Spacer(Modifier.height(12.dp))
                Button(onClick = actions.onChooseExternalApp, modifier = Modifier.fillMaxWidth()) {
                    Text("Choose compatibility app")
                }
                Spacer(Modifier.height(8.dp))
                Muted(plan.note)
            }
            is LaunchPlan.ExternalAppMissing -> {
                Muted("${plan.configuredLabel} is no longer installed. Reinstall it yourself, or choose another app.")
                Spacer(Modifier.height(8.dp))
                Steps(plan.steps)
                Spacer(Modifier.height(12.dp))
                Button(onClick = actions.onChooseExternalApp, modifier = Modifier.fillMaxWidth()) {
                    Text("Choose compatibility app")
                }
            }
            is LaunchPlan.Unsupported -> {
                Bullets(plan.info.reasons)
                Spacer(Modifier.height(8.dp))
                InfoRow("Requires", plan.info.requiredEnvironment)
                InfoRow("Testing", plan.info.testStatus)
            }
        }
    }
}

@Composable
private fun Muted(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun Bullets(lines: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        lines.forEach { Text("•  $it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

@Composable
private fun Steps(steps: List<String>) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        steps.forEachIndexed { i, step ->
            Text("${i + 1}.  $step", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface)
        }
    }
}
