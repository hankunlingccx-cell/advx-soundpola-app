package com.soundpola.app.ui.record

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.ui.components.PrimaryButton
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary700
import com.soundpola.app.ui.theme.Radii
import com.soundpola.app.ui.theme.Spacing

/** first.md §7.1 权限说明 */
@Composable
fun PermissionScreen(onContinue: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(horizontal = Spacing.pageHorizontal, vertical = Spacing.section),
        verticalArrangement = Arrangement.SpaceBetween,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(40.dp))
            Text("SoundPola", color = Ink950, fontSize = 28.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(6.dp))
            Text("声音的拍立得", color = Ink600, fontSize = 14.sp)
            Spacer(Modifier.height(Spacing.block))
            SoundVisualCanvas(
                seed = 2026,
                active = false,
                modifier = Modifier
                    .size(220.dp)
                    .clip(RoundedCornerShape(Radii.collectionCard))
                    .background(Primary50),
            )
            Spacer(Modifier.height(Spacing.block))
            PermissionCard("麦克风", "用于录制你想保存的声音。")
            Spacer(Modifier.height(Spacing.tight))
            PermissionCard("定位（可选）", "用于自动记录声音发生的地点。拒绝后仍可录音。")
        }
        Column(Modifier.fillMaxWidth()) {
            Text(
                text = "继续后将依次申请麦克风与定位权限。",
                color = Ink600,
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(bottom = Spacing.item),
            )
            PrimaryButton(text = "继续", onClick = onContinue)
        }
    }
}

@Composable
private fun PermissionCard(title: String, body: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(Primary50)
            .padding(Spacing.item),
    ) {
        Text(title, color = Primary700, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
        Spacer(Modifier.height(6.dp))
        Text(body, color = Ink600, fontSize = 14.sp, lineHeight = 22.sp)
    }
}
