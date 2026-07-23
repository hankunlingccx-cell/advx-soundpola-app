package com.soundpola.app.ui.record

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
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
import com.soundpola.app.ui.theme.Radii
import com.soundpola.app.ui.theme.Spacing

/** first.md §7.2 Record 录音首页 — designstyle §10.1 */
@Composable
fun RecordHomeScreen(onStartRecord: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(horizontal = Spacing.pageHorizontal),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = Spacing.item),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Record", color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            Text("帮助", color = Ink400, fontSize = 13.sp)
        }

        Spacer(Modifier.weight(0.28f))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(340.dp)
                .clip(RoundedCornerShape(Radii.collectionCard))
                .background(Primary50),
            contentAlignment = Alignment.Center,
        ) {
            SoundVisualCanvas(
                seed = 88,
                active = false,
                modifier = Modifier.fillMaxSize().padding(Spacing.section),
            )
        }

        Spacer(Modifier.height(Spacing.section))
        Text(
            text = "点击开始捕捉声音",
            color = Ink600,
            fontSize = 15.sp,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )
        Spacer(Modifier.height(Spacing.item))
        Box(Modifier.align(Alignment.CenterHorizontally)) {
            RecordFab(recording = false, onClick = onStartRecord)
        }
        Spacer(Modifier.weight(0.32f))
    }
}
