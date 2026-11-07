package com.retroplay.app.presentation.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.retroplay.app.R
import com.retroplay.app.core.designsystem.component.CardHeader
import com.retroplay.app.core.designsystem.component.RetroCard
import com.retroplay.app.core.designsystem.component.SectionLabel
import com.retroplay.app.core.designsystem.theme.RetroGradients

@Composable
fun HomeScreen(onOpenDeviceInfo: () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier
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
            }
        }

        SectionLabel("Your device")
        RetroCard(onClick = onOpenDeviceInfo) {
            CardHeader(stringResource(R.string.title_device_info), Icons.Filled.PhoneAndroid)
            Text(
                "See the hardware profile measured on this phone and how it compares with the Pixel 9 reference.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        SectionLabel("Game library")
        RetroCard {
            Text(
                "The game library, launchers and import tools are not part of this build yet. " +
                    "RetroPlay never bundles or downloads games.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
