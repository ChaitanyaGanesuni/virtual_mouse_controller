package com.retroplay.app.presentation.gamedetail

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.retroplay.app.core.designsystem.theme.RetroPlayTheme
import com.retroplay.app.domain.game.GameCatalogue
import com.retroplay.app.domain.launch.InstalledApp
import com.retroplay.app.domain.launch.LaunchPlan
import com.retroplay.app.domain.launch.UnsupportedInfo
import com.retroplay.app.launcher.ExternalEmulatorLauncher
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class GameDetailContentTest {
    @get:Rule val composeRule = createComposeRule()

    private val pcGame = GameCatalogue.initialGames.first { it.id == "gta-vice-city" }
    private val androidGame = GameCatalogue.initialGames.first { it.id == "gta-vice-city-android" }

    @Test fun unconfiguredPcGameOffersChoosingAnAppNotAPlayButton() {
        var chosen = 0
        val plan = LaunchPlan.ExternalNotConfigured(
            ExternalEmulatorLauncher.manualSteps(pcGame, null),
            ExternalEmulatorLauncher.NO_DIRECT_LAUNCH_NOTE,
        )
        composeRule.setContent {
            RetroPlayTheme {
                GameDetailContent(GameDetailUiState.Ready(pcGame, plan), {}, {}, {}, LaunchActions(onChooseExternalApp = { chosen++ }))
            }
        }
        composeRule.onNodeWithText("Grand Theft Auto: Vice City").assertIsDisplayed()
        composeRule.onNodeWithText("Choose compatibility app").performScrollTo().performClick()
        composeRule.onNodeWithText("Play").assertDoesNotExist()
        assertEquals(1, chosen)
    }

    @Test fun installedAndroidGameShowsPlay() {
        var launches = 0
        val plan = LaunchPlan.AndroidReady(InstalledApp("com.rockstargames.gtavc", "GTA: Vice City"))
        composeRule.setContent {
            RetroPlayTheme {
                GameDetailContent(GameDetailUiState.Ready(androidGame, plan), {}, {}, {}, LaunchActions(onLaunch = { launches++ }))
            }
        }
        composeRule.onNodeWithText("Play").performScrollTo().performClick()
        assertEquals(1, launches)
    }

    @Test fun missingAndroidGameOffersStoreListingAndLinkingOnly() {
        var store: String? = null
        val plan = LaunchPlan.AndroidNotInstalled("com.rockstargames.gtavc", listOf("Not installed."))
        composeRule.setContent {
            RetroPlayTheme {
                GameDetailContent(GameDetailUiState.Ready(androidGame, plan), {}, {}, {}, LaunchActions(onOpenStore = { store = it }))
            }
        }
        composeRule.onNodeWithText("Play").assertDoesNotExist()
        composeRule.onNodeWithText("Link installed app").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("Store listing").performScrollTo().performClick()
        assertEquals("com.rockstargames.gtavc", store)
    }

    @Test fun unsupportedGameExplainsWhy() {
        val plan = LaunchPlan.Unsupported(UnsupportedInfo(listOf("Reason A"), "Windows PC: needs X", "Not tested on this device."))
        composeRule.setContent { RetroPlayTheme { GameDetailContent(GameDetailUiState.Ready(pcGame, plan), {}, {}, {}) } }
        composeRule.onNodeWithText("Cannot launch").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("•  Reason A").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("Not tested on this device.").performScrollTo().assertIsDisplayed()
    }

    @Test fun favouriteBackAndNotesCallbacks() {
        var favourite: Boolean? = null
        var savedNotes: String? = null
        var backs = 0
        composeRule.setContent {
            RetroPlayTheme {
                GameDetailContent(GameDetailUiState.Ready(pcGame, null), { backs++ }, { favourite = it }, { savedNotes = it })
            }
        }
        composeRule.onNodeWithContentDescription("Add to favourites").performClick()
        composeRule.onNodeWithContentDescription("Back").performClick()
        composeRule.onNodeWithText("Setup steps, settings that worked, reminders…").performScrollTo().performTextInput("VirGL")
        composeRule.onNodeWithText("Save notes").performScrollTo().performClick()

        assertEquals(true, favourite)
        assertEquals(1, backs)
        assertEquals("VirGL", savedNotes)
    }
}
