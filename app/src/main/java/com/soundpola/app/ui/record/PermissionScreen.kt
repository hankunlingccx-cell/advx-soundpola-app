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

@Composable
fun PermissionScreen(onContinue: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.SpaceBetween,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(48.dp))
            Text(
                text = "SoundPola",
                color = Ink950,
                fontSize = 28.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = "声音的拍立得",
                color = Ink600,
                fontSize = 14.sp,
            )
            Spacer(Modifier.height(36.dp))
            SoundVisualCanvas(
                seed = 2026,
                active = false,
                modifier = Modifier
                    .size(220.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(Primary50),
            )
            Spacer(Modifier.height(36.dp))
            PermissionCard(
                title = "麦克风",
                body = "用于录制你想保存的声音。这是必需权限。",
            )
            Spacer(Modifier.height(12.dp))
            PermissionCard(
                title = "定位（可选）",
                body = "用于自动记录声音发生的地点。拒绝后仍可录音。",
            )
        }
        Column(modifier = Modifier.fillMaxWidth()) {
            Text(
                text = "继续即表示你了解权限用途。定位可随时在系统设置中开启。",
                color = Ink600,
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 16.dp),
            )
            PrimaryButton(text = "继续", onClick = onContinue)
            Spacer(Modifier.height(12.dp))
        }
    }
}

@Composable
private fun PermissionCard(title: String, body: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(Primary50)
            .padding(16.dp),
    ) {
        Text(
            text = title,
            color = Primary700,
            fontWeight = FontWeight.SemiBold,
            fontSize = 15.sp,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = body,
            color = Ink600,
            fontSize = 14.sp,
            lineHeight = 22.sp,
        )
    }
}