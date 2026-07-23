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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.data.formatDuration
import com.soundpola.app.ui.components.RecordFab
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.theme.DarkCanvas
import com.soundpola.app.ui.theme.DarkSecondary
import com.soundpola.app.ui.theme.DarkSurface
import com.soundpola.app.ui.theme.DarkText
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary500
import kotlinx.coroutines.delay

@Composable
fun RecordingScreen(
    onCancel: () -> Unit,
    onComplete: (durationSec: Int) -> Unit,
) {
    var seconds by remember { mutableIntStateOf(0) }
    var paused by remember { mutableStateOf(false) }
    var showAbort by remember { mutableStateOf(false) }

    LaunchedEffect(paused) {
        while (!paused) {
            delay(1000)
            seconds += 1
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(DarkCanvas)
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = "取消",
                color = DarkSecondary,
                modifier = Modifier.clickable { showAbort = true },
            )
            Text(
                text = if (paused) "录音已暂停" else "正在录音",
                color = DarkText,
                fontWeight = FontWeight.Medium,
            )
            Spacer(modifier = Modifier.size(32.dp))
        }

        Spacer(modifier = Modifier.weight(0.3f))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(300.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(DarkSurface),
            contentAlignment = Alignment.Center,
        ) {
            SoundVisualCanvas(
                seed = 404,
                active = !paused,
                dark = true,
                modifier = Modifier.fillMaxSize().padding(20.dp),
            )
        }

        Spacer(modifier = Modifier.height(28.dp))
        Text(
            text = formatDuration(seconds),
            color = DarkText,
            fontSize = 40.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = if (paused) "轻触继续" else "环境音量正常",
            color = DarkSecondary,
            fontSize = 13.sp,
        )

        Spacer(modifier = Modifier.weight(0.35f))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(CircleShape)
                    .background(DarkSurface)
                    .clickable { paused = !paused },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = if (paused) "继续" else "暂停",
                    color = DarkText,
                    fontSize = 12.sp,
                )
            }
            RecordFab(
                recording = true,
                onClick = { onComplete(seconds.coerceAtLeast(1)) },
            )
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(CircleShape)
                    .background(Primary500)
                    .clickable { onComplete(seconds.coerceAtLeast(1)) },
                contentAlignment = Alignment.Center,
            ) {
                Text("完成", color = Ink950, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        Spacer(modifier = Modifier.height(24.dp))
    }

    if (showAbort) {
        AlertDialog(
            onDismissRequest = { showAbort = false },
            title = { Text("放弃本次录音？") },
            text = { Text("当前录制内容不会被保存。") },
            confirmButton = {
                TextButton(onClick = onCancel) { Text("放弃录音") }
            },
            dismissButton = {
                TextButton(onClick = { showAbort = false }) { Text("继续录音") }
            },
        )
    }
}
