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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.ui.components.RecordFab
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.components.TimerText
import com.soundpola.app.ui.theme.DarkCanvas
import com.soundpola.app.ui.theme.DarkSecondary
import com.soundpola.app.ui.theme.DarkSurface
import com.soundpola.app.ui.theme.DarkText
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.Radii
import com.soundpola.app.ui.theme.Spacing
import kotlinx.coroutines.delay

/** first.md §7.3 录音中 / 已暂停 */
@Composable
fun RecordingScreen(onCancel: () -> Unit, onComplete: (Int) -> Unit) {
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
            .padding(Spacing.pageHorizontal),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.item),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("取消", color = DarkSecondary, modifier = Modifier.clickable { showAbort = true })
            Text(
                text = if (paused) "录音已暂停" else "正在录音",
                color = DarkText,
                fontWeight = FontWeight.Medium,
            )
            Spacer(Modifier.size(32.dp))
        }

        Spacer(Modifier.weight(0.25f))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(320.dp)
                .clip(RoundedCornerShape(Radii.collectionCard))
                .background(DarkSurface),
            contentAlignment = Alignment.Center,
        ) {
            SoundVisualCanvas(
                seed = 404,
                active = !paused,
                dark = true,
                modifier = Modifier.fillMaxSize().padding(Spacing.section),
            )
        }

        Spacer(Modifier.height(Spacing.section))
        TimerText(seconds = seconds, dark = true)
        Spacer(Modifier.height(8.dp))
        Text(
            text = if (paused) "轻触继续" else "环境音量正常",
            color = DarkSecondary,
            fontSize = 13.sp,
        )

        Spacer(Modifier.weight(0.3f))

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
                Text(if (paused) "继续" else "暂停", color = DarkText, fontSize = 12.sp)
            }
            RecordFab(recording = !paused, onClick = { onComplete(seconds.coerceAtLeast(1)) })
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
        Spacer(Modifier.height(Spacing.section))
    }

    if (showAbort) {
        AlertDialog(
            onDismissRequest = { showAbort = false },
            title = { Text("放弃本次录音？") },
            text = { Text("当前录制内容不会被保存。") },
            confirmButton = { TextButton(onClick = onCancel) { Text("放弃录音", color = com.soundpola.app.ui.theme.Error) } },
            dismissButton = { TextButton(onClick = { showAbort = false }) { Text("继续录音") } },
        )
    }
}
