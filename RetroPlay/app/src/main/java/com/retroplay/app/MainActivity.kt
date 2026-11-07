package com.retroplay.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.retroplay.app.core.designsystem.theme.RetroPlayTheme
import com.retroplay.app.navigation.RetroPlayAppUi
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RetroPlayTheme {
                RetroPlayAppUi()
            }
        }
    }
}
