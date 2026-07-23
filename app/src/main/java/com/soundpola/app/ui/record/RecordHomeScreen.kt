package com.soundpola.app.ui.record

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.ui.components.RecordFab
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary50

@Composable
fun RecordHomeScreen(onStartRecord: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(16.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("SoundPola", color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            Text("帮助", color = Ink400, fontSize = 13.sp)
        }

        Spacer(modifier = Modifier.weight(0.35f))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(320.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(Primary50),
            contentAlignment = Alignment.Center,
        ) {
            SoundVisualCanvas(
                seed = 88,
                active = false,
                modifier = Modifier.fillMaxSize().padding(24.dp),
            )
        }

        Spacer(modifier = Modifier.height(24.dp))
        Text("点击开始捕捉声音", color = Ink600, fontSize = 15.sp)
        Spacer(modifier = Modifier.height(20.dp))
        RecordFab(recording = false, onClick = onStartRecord)
        Spacer(modifier = Modifier.weight(0.45f))
    }
}
