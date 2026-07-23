package com.soundpola.app.ui.drafts

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.data.SoundMemory
import com.soundpola.app.data.SoundRepository
import com.soundpola.app.data.SoundStatus
import com.soundpola.app.data.formatDuration
import com.soundpola.app.data.formatRecordedAt
import com.soundpola.app.ui.components.PrimaryButton
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.components.StatusChip
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.White

@Composable
fun DraftsScreen(
    onOpenDetail: (String) -> Unit,
    onPress: (String) -> Unit,
    onStartRecord: () -> Unit,
) {
    val drafts = SoundRepository.drafts()
    var playingId by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(horizontal = 20.dp),
    ) {
        Spacer(modifier = Modifier.height(16.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Drafts", color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            Text("${drafts.size} 条暂存", color = Ink400, fontSize = 13.sp)
        }
        Spacer(modifier = Modifier.height(16.dp))

        if (drafts.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                SoundVisualCanvas(
                    seed = 1,
                    active = false,
                    modifier = Modifier
                        .size(140.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .background(Primary50),
                )
                Spacer(modifier = Modifier.height(20.dp))
                Text("还没有暂存的声音", color = Ink950, fontWeight = FontWeight.SemiBold)
                Spacer(modifier = Modifier.height(8.dp))
                Text("去捕捉此刻的声音", color = Ink600, fontSize = 14.sp)
                Spacer(modifier = Modifier.height(20.dp))
                Box(modifier = Modifier.width(200.dp)) {
                    PrimaryButton(text = "开始录音", onClick = onStartRecord)
                }
            }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(drafts, key = { it.id }) { item ->
                    DraftCard(
                        item = item,
                        playing = playingId == item.id,
                        onPlay = {
                            playingId = if (playingId == item.id) null else item.id
                        },
                        onPress = { onPress(item.id) },
                        onOpen = { onOpenDetail(item.id) },
                    )
                }
                item { Spacer(modifier = Modifier.height(24.dp)) }
            }
        }
    }
}

@Composable
private fun DraftCard(
    item: SoundMemory,
    playing: Boolean,
    onPlay: () -> Unit,
    onPress: () -> Unit,
    onOpen: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(White)
            .clickable(onClick = onOpen)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(Primary50),
        ) {
            SoundVisualCanvas(
                seed = item.visualSeed,
                active = playing,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(6.dp),
            )
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(item.title, color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "${formatRecordedAt(item.recordedAtMillis)} · ${formatDuration(item.durationSec)} · ${item.category}",
                color = Ink600,
                fontSize = 12.sp,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StatusChip(item.status)
                if (item.status == SoundStatus.Drafted || item.status == SoundStatus.WriteFailed) {
                    Text(
                        text = "Press",
                        color = Primary500,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 13.sp,
                        modifier = Modifier.clickable(onClick = onPress),
                    )
                }
            }
        }
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(Primary50)
                .clickable(onClick = onPlay),
            contentAlignment = Alignment.Center,
        ) {
            Text(if (playing) "‖" else "▶", color = Ink950, fontSize = 12.sp)
        }
    }
}

@Composable
fun DraftDetailScreen(
    id: String,
    onBack: () -> Unit,
    onPress: () -> Unit,
    onDeleted: () -> Unit,
) {
    val item = SoundRepository.get(id)
    var confirmDelete by remember { mutableStateOf(false) }
    var playing by remember { mutableStateOf(false) }

    if (item == null) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Text(text = "声音不存在", color = Ink600)
        }
    } else {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(CanvasBg)
                .padding(20.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(text = "返回", color = Ink600, modifier = Modifier.clickable(onClick = onBack))
                Text(text = "详情", color = Ink950, fontWeight = FontWeight.SemiBold)
                Text(text = "删除", color = Ink400, modifier = Modifier.clickable { confirmDelete = true })
            }
            Spacer(modifier = Modifier.height(20.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(280.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(Primary50)
                    .clickable { playing = !playing },
                contentAlignment = Alignment.Center,
            ) {
                SoundVisualCanvas(
                    seed = item.visualSeed,
                    active = playing,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(20.dp),
                )
            }
            Spacer(modifier = Modifier.height(20.dp))
            Text(text = item.title, color = Ink950, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(8.dp))
            StatusChip(item.status)
            Spacer(modifier = Modifier.height(12.dp))
            Text(text = "#${item.category}", color = Ink600, fontSize = 14.sp)
            if (item.description.isNotBlank()) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = item.description,
                    color = Ink600,
                    fontSize = 15.sp,
                    lineHeight = 24.sp,
                )
            }
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "${formatRecordedAt(item.recordedAtMillis)} · ${item.locationLabel} · ${formatDuration(item.durationSec)}",
                color = Ink400,
                fontSize = 12.sp,
            )
            Spacer(modifier = Modifier.weight(1f))
            PrimaryButton(text = "写入声片", onClick = onPress)
            Spacer(modifier = Modifier.height(12.dp))
        }
    }

    if (confirmDelete && item != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("删除这段声音？") },
            text = { Text("录音、声音视觉和相关记忆信息将被永久移除。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (SoundRepository.delete(id)) onDeleted()
                        confirmDelete = false
                    },
                ) { Text("确认删除") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("取消") }
            },
        )
    }
}
