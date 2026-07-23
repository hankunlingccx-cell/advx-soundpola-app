package com.soundpola.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.soundpola.app.ui.navigation.SoundpolaApp
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.SoundpolaTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            SoundpolaTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = CanvasBg,
                ) {
                    SoundpolaApp()
                }
            }
        }
    }
}
