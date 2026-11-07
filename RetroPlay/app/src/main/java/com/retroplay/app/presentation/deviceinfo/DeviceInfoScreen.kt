package com.retroplay.app.presentation.deviceinfo

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Android
import androidx.compose.material.icons.automirrored.filled.CompareArrows
import androidx.compose.material.icons.filled.DeveloperBoard
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.ViewInAr
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.retroplay.app.R
import com.retroplay.app.core.designsystem.component.CardHeader
import com.retroplay.app.core.designsystem.component.InfoRow
import com.retroplay.app.core.designsystem.component.RetroCard
import com.retroplay.app.core.designsystem.theme.RetroError
import com.retroplay.app.core.designsystem.theme.RetroGradients
import com.retroplay.app.core.designsystem.theme.RetroSuccess
import com.retroplay.app.core.designsystem.theme.RetroTextSecondary
import com.retroplay.app.core.designsystem.theme.RetroWarning
import com.retroplay.app.domain.model.ComparisonRow
import com.retroplay.app.domain.model.ComparisonVerdict
import com.retroplay.app.domain.model.ReferenceDeviceProfile
import java.text.DateFormat
import java.util.Date

const val DEVICE_INFO_LIST_TAG = "device_info_list"

@Composable
fun DeviceInfoScreen(onBack: () -> Unit, viewModel: DeviceInfoViewModel = hiltViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    DeviceInfoContent(state = state, onBack = onBack, onRefresh = viewModel::refresh)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceInfoContent(state: DeviceInfoUiState, onBack: () -> Unit, onRefresh: () -> Unit) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_device_info)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.action_back))
                    }
                },
                actions = {
                    IconButton(onClick = onRefresh, enabled = state !is DeviceInfoUiState.Loading) {
                        Icon(Icons.Filled.Refresh, contentDescription = stringResource(R.string.action_refresh))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        AnimatedContent(
            targetState = state,
            contentKey = { it::class },
            transitionSpec = { fadeIn(tween(250)) togetherWith fadeOut(tween(150)) },
            label = "device_info_state",
        ) { s ->
            when (s) {
                DeviceInfoUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
                is DeviceInfoUiState.Error -> Box(Modifier.fillMaxSize().padding(padding).padding(16.dp), contentAlignment = Alignment.Center) {
                    RetroCard {
                        Text("Could not read device information", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(8.dp))
                        Text(s.message, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        TextButton(onClick = onRefresh) { Text(stringResource(R.string.action_retry)) }
                    }
                }
                is DeviceInfoUiState.Ready -> ProfileList(s, padding)
            }
        }
    }
}

@Composable
private fun ProfileList(state: DeviceInfoUiState.Ready, padding: PaddingValues) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().testTag(DEVICE_INFO_LIST_TAG),
        contentPadding = PaddingValues(
            start = 16.dp,
            end = 16.dp,
            top = padding.calculateTopPadding() + 8.dp,
            bottom = padding.calculateBottomPadding() + 24.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "summary") { SummaryCard(state) }
        if (state.showComparison) {
            item(key = "comparison") { ComparisonCard(state.reference, state.comparison) }
        }
        items(state.sections, key = { it.kind }) { section ->
            RetroCard {
                CardHeader(section.title, section.kind.icon())
                section.rows.forEach { (label, value) -> InfoRow(label, value) }
            }
        }
    }
}

@Composable
private fun SummaryCard(state: DeviceInfoUiState.Ready) {
    val p = state.profile
    Box(
        Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.large)
            .background(RetroGradients.Hero)
            .padding(20.dp),
    ) {
        Column {
            Text("Measured on this device", style = MaterialTheme.typography.labelMedium, color = Color.White.copy(alpha = 0.8f))
            Spacer(Modifier.height(4.dp))
            Text("${p.identity.manufacturer} ${p.identity.model}", style = MaterialTheme.typography.headlineSmall, color = Color.White)
            Text("Android ${p.os.release} · API ${p.os.apiLevel}", style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.9f))
            Spacer(Modifier.height(8.dp))
            Text(
                "Captured ${DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date(p.capturedAtEpochMillis))}",
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.7f),
            )
        }
    }
}

@Composable
private fun ComparisonCard(reference: ReferenceDeviceProfile, rows: List<ComparisonRow>) {
    RetroCard {
        CardHeader("${reference.displayName} reference", Icons.AutoMirrored.Filled.CompareArrows)
        Text(
            "Reference values come from the published specification and are not measurements. " +
                "Measured values are read from this device at runtime.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(8.dp))
        rows.forEachIndexed { index, row ->
            if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            ComparisonRowItem(row)
        }
    }
}

@Composable
private fun ComparisonRowItem(row: ComparisonRow) {
    Column(Modifier.padding(vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(row.field.label, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            VerdictChip(row.verdict)
        }
        Spacer(Modifier.height(4.dp))
        Text("Reference: ${row.reference}", style = MaterialTheme.typography.bodySmall, color = RetroTextSecondary)
        Text("Measured: ${row.measured}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface)
        row.note?.let {
            Text(it, style = MaterialTheme.typography.labelSmall, color = RetroTextSecondary)
        }
    }
}

@Composable
private fun VerdictChip(verdict: ComparisonVerdict) {
    val (label, color) = when (verdict) {
        ComparisonVerdict.MATCH -> "Matches" to RetroSuccess
        ComparisonVerdict.DIFFERENT -> "Differs" to RetroWarning
        ComparisonVerdict.UNAVAILABLE -> "Unavailable" to RetroError
    }
    Row(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.15f))
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.width(6.dp).height(6.dp).clip(RoundedCornerShape(50)).background(color))
        Spacer(Modifier.width(6.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = color)
    }
}

private fun SectionKind.icon(): ImageVector = when (this) {
    SectionKind.DEVICE -> Icons.Filled.PhoneAndroid
    SectionKind.ANDROID -> Icons.Filled.Android
    SectionKind.CPU -> Icons.Filled.DeveloperBoard
    SectionKind.MEMORY -> Icons.Filled.Memory
    SectionKind.GPU -> Icons.Filled.Videocam
    SectionKind.GRAPHICS_APIS -> Icons.Filled.ViewInAr
    SectionKind.DISPLAY -> Icons.Filled.Tv
    SectionKind.STORAGE -> Icons.Filled.Storage
    SectionKind.THERMAL -> Icons.Filled.Thermostat
}
