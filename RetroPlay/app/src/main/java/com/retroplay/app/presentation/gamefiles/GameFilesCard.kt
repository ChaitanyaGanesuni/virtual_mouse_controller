package com.retroplay.app.presentation.gamefiles

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.retroplay.app.core.designsystem.component.CardHeader
import com.retroplay.app.core.designsystem.component.InfoRow
import com.retroplay.app.core.designsystem.component.RetroCard
import com.retroplay.app.core.designsystem.theme.RetroSuccess
import com.retroplay.app.core.designsystem.theme.RetroWarning
import com.retroplay.app.core.util.Formatters
import com.retroplay.app.domain.model.GameInstallation
import com.retroplay.app.domain.model.ImportValidity
import com.retroplay.app.storage.ExecutableCandidate
import java.text.DateFormat
import java.util.Date

data class GameFilesActions(
    val onPickFolder: () -> Unit = {},
    val onRevalidate: () -> Unit = {},
    val onRemoveImport: () -> Unit = {},
)

/** Shows the imported file reference for a Windows game, or how to import one. */
@Composable
fun GameFilesCard(installation: GameInstallation?, actions: GameFilesActions) {
    var confirmRemove by remember { mutableStateOf(false) }
    RetroCard {
        CardHeader("Game files", Icons.Filled.FolderOpen)
        if (installation == null) {
            Text(
                "Select the folder that holds your legally obtained copy of this game, then choose its .exe file. " +
                    "RetroPlay only records where the files are; it never copies, runs or deletes them.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))
            Button(onClick = actions.onPickFolder, modifier = Modifier.fillMaxWidth()) { Text("Import game files") }
        } else {
            val ok = installation.validity == ImportValidity.VALID
            Text(
                installation.validity.label,
                style = MaterialTheme.typography.labelLarge,
                color = if (ok) RetroSuccess else RetroWarning,
            )
            installation.message?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.height(4.dp))
            InfoRow("Folder", installation.folderDisplayPath)
            InfoRow("Executable", installation.executableRelativePath)
            InfoRow("Size", Formatters.bytes(installation.executableSizeBytes, binary = false))
            InfoRow("Imported", DateFormat.getDateInstance().format(Date(installation.importedAtEpochMillis)))
            InfoRow("Last checked", DateFormat.getDateTimeInstance().format(Date(installation.lastValidatedAtEpochMillis)))
            Spacer(Modifier.height(8.dp))
            Text(
                "Other apps, including your compatibility app, cannot use RetroPlay's access to this folder. " +
                    "If that app can't see it, copy the folder to a location it can read.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = actions.onRevalidate) { Text("Re-check") }
                OutlinedButton(onClick = actions.onPickFolder) { Text(if (ok) "Change" else "Select again") }
            }
            TextButton(onClick = { confirmRemove = true }) { Text("Remove import") }
        }
    }
    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text("Remove import?") },
            text = { Text("RetroPlay will forget where these files are. Your game files are not deleted or changed.") },
            confirmButton = {
                TextButton(onClick = { confirmRemove = false; actions.onRemoveImport() }) { Text("Remove") }
            },
            dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text("Cancel") } },
        )
    }
}

/** Dialogs for the scan → choose → validate steps. */
@Composable
fun ImportFlowDialogs(
    state: ImportFlowState,
    onChoose: (ExecutableCandidate) -> Unit,
    onCancel: () -> Unit,
    onDismissResult: () -> Unit,
) {
    when (state) {
        ImportFlowState.Idle -> Unit
        ImportFlowState.Scanning, ImportFlowState.Validating -> AlertDialog(
            onDismissRequest = {},
            title = { Text(if (state == ImportFlowState.Scanning) "Looking for .exe files…" else "Checking the file…") },
            text = { Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { CircularProgressIndicator() } },
            confirmButton = {},
        )
        is ImportFlowState.ChooseExecutable -> ChooseExecutableDialog(state, onChoose, onCancel)
        is ImportFlowState.Done -> AlertDialog(
            onDismissRequest = onDismissResult,
            title = { Text("Files imported") },
            text = {
                Text(
                    "${state.installation.executableRelativePath} in ${state.installation.folderDisplayPath} is registered. " +
                        "Nothing was run or copied.",
                )
            },
            confirmButton = { TextButton(onClick = onDismissResult) { Text("OK") } },
        )
        is ImportFlowState.Error -> AlertDialog(
            onDismissRequest = onDismissResult,
            title = { Text("Import failed") },
            text = { Text(state.message) },
            confirmButton = { TextButton(onClick = onDismissResult) { Text("OK") } },
        )
    }
}

@Composable
private fun ChooseExecutableDialog(
    state: ImportFlowState.ChooseExecutable,
    onChoose: (ExecutableCandidate) -> Unit,
    onCancel: () -> Unit,
) {
    var selected by remember(state) { mutableStateOf(state.candidates.first()) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("Choose the game's executable") },
        text = {
            Column {
                Text(state.folderDisplayPath, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.secondary)
                if (state.truncated) {
                    Text(
                        "Large folder: only part of it was searched. Pick the game's own folder if the right file is missing.",
                        style = MaterialTheme.typography.bodySmall,
                        color = RetroWarning,
                    )
                }
                Spacer(Modifier.height(8.dp))
                LazyColumn(Modifier.heightIn(max = 360.dp)) {
                    items(state.candidates, key = { it.relativePath }) { c ->
                        Row(
                            Modifier.fillMaxWidth().clickable { selected = c }.padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = c == selected, onClick = { selected = c })
                            Column {
                                Text(c.relativePath, style = MaterialTheme.typography.bodyMedium)
                                Text(
                                    Formatters.bytes(c.sizeBytes, binary = false),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { onChoose(selected) }) { Text("Import") } },
        dismissButton = { TextButton(onClick = onCancel) { Text("Cancel") } },
    )
}
