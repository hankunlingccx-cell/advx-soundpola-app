package com.soundpola.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = Primary500,
    onPrimary = Ink950,
    primaryContainer = Primary100,
    onPrimaryContainer = Primary700,
    secondary = Primary600,
    onSecondary = Ink950,
    background = CanvasBg,
    onBackground = Ink950,
    surface = White,
    onSurface = Ink950,
    surfaceVariant = Surface100,
    onSurfaceVariant = Ink600,
    outline = Line200,
    error = Error,
)

private val DarkColors = darkColorScheme(
    primary = Primary500,
    onPrimary = Ink950,
    background = DarkCanvas,
    onBackground = DarkText,
    surface = DarkSurface,
    onSurface = DarkText,
    surfaceVariant = DarkSurface,
    onSurfaceVariant = DarkSecondary,
    outline = DarkSecondary.copy(alpha = 0.35f),
    error = Error,
)

@Composable
fun SoundpolaTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = SoundpolaTypography,
        content = content,
    )
}
