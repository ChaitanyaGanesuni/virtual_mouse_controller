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
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

@RunWith(AndroidJUnit4::class)
@Config(sdk = [35])
class GameDetailContentTest {
    @get:Rule val composeRule = createComposeRule()

    private val game = GameCatalogue.initialGames.first { it.id == "gta-vice-city" }

    @Test fun showsMetadataWithoutAFakeLaunchButton() {
        composeRule.setContent { RetroPlayTheme { GameDetailContent(GameDetailUiState.Ready(game), {}, {}, {}) } }
        composeRule.onNodeWithText("Grand Theft Auto: Vice City").assertIsDisplayed()
        composeRule.onNodeWithText("2003").assertIsDisplayed()
        composeRule.onNodeWithText("Launching from RetroPlay is not available in this build.").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("Not tested").performScrollTo().assertIsDisplayed()
        composeRule.onNodeWithText("Play", substring = false).assertDoesNotExist()
    }

    @Test fun favouriteBackAndNotesCallbacks() {
        var favourite: Boolean? = null
        var savedNotes: String? = null
        var backs = 0
        composeRule.setContent {
            RetroPlayTheme {
                GameDetailContent(GameDetailUiState.Ready(game), { backs++ }, { favourite = it }, { savedNotes = it })
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
