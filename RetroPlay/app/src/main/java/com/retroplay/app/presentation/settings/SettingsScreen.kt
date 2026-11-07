package com.retroplay.app.presentation.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.CompareArrows
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.retroplay.app.BuildConfig
import com.retroplay.app.R
import com.retroplay.app.core.designsystem.component.CardHeader
import com.retroplay.app.core.designsystem.component.InfoRow
import com.retroplay.app.core.designsystem.component.RetroCard
import com.retroplay.app.core.designsystem.component.SectionLabel
import com.retroplay.app.domain.repository.UserPreferences

@Composable
fun SettingsScreen(onOpenDeviceInfo: () -> Unit, onOpenCompatibilityReport: () -> Unit, viewModel: SettingsViewModel = hiltViewModel()) {
    val prefs by viewModel.preferences.collectAsStateWithLifecycle()
    SettingsContent(
        preferences = prefs,
        onOpenDeviceInfo = onOpenDeviceInfo,
        onOpenCompatibilityReport = onOpenCompatibilityReport,
        onShowComparisonChange = viewModel::setShowReferenceComparison,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsContent(
    preferences: UserPreferences,
    onOpenDeviceInfo: () -> Unit,
    onOpenCompatibilityReport: () -> Unit,
    onShowComparisonChange: (Boolean) -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_settings)) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionLabel("Device")
            NavigationCard(
                title = stringResource(R.string.title_device_info),
                icon = Icons.Filled.PhoneAndroid,
                description = "Runtime hardware profile: CPU, memory, GPU, graphics APIs, display and storage.",
                onClick = onOpenDeviceInfo,
            )
            NavigationCard(
                title = "Compatibility report",
                icon = Icons.Filled.Assessment,
                description = "Recorded compatibility status of every game on this device.",
                onClick = onOpenCompatibilityReport,
            )

            SectionLabel("Preferences")
            RetroCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        CardHeader("Pixel 9 reference comparison", Icons.AutoMirrored.Filled.CompareArrows)
                        Text(
                            "Compare measured hardware against the Pixel 9 specification on the Device information screen.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(Modifier.width(8.dp))
                    Switch(checked = preferences.showReferenceComparison, onCheckedChange = onShowComparisonChange)
                }
            }

            SectionLabel("About")
            RetroCard {
                CardHeader("RetroPlay", Icons.Filled.Info)
                InfoRow("Version", BuildConfig.VERSION_NAME)
                InfoRow("Build type", BuildConfig.BUILD_TYPE)
                Text(
                    "RetroPlay is a personal game library and launcher. It does not include or download any games.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun NavigationCard(title: String, icon: ImageVector, description: String, onClick: () -> Unit) {
    RetroCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                CardHeader(title, icon)
                Text(description, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(Modifier.width(8.dp))
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
        }
    }
}
