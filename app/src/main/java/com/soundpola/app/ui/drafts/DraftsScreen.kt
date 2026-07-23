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
import com.soundpola.app.ui.components.FilterChipRow
import com.soundpola.app.ui.components.PageHeader
import com.soundpola.app.ui.components.PrimaryButton
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.components.StatusChip
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.Primary700
import com.soundpola.app.ui.theme.Radii
import com.soundpola.app.ui.theme.Spacing
import com.soundpola.app.ui.theme.White

private val DraftFilters = listOf("全部", "已暂存", "处理中", "失败")

/** first.md §7.5 Drafts 暂存列表 — designstyle §10.3 */
@Composable
fun DraftsScreen(
    onOpenDetail: (String) -> Unit,
    onPress: (String) -> Unit,
    onStartRecord: () -> Unit,
) {
    var filter by remember { mutableStateOf("全部") }
    var playingId by remember { mutableStateOf<String?>(null) }
    val all = SoundRepository.drafts()
    val drafts = when (filter) {
        "已暂存" -> all.filter { it.status == SoundStatus.Drafted }
        "处理中" -> all.filter { it.status == SoundStatus.Writing || it.status == SoundStatus.ChainPending }
        "失败" -> all.filter { it.status == SoundStatus.WriteFailed || it.status == SoundStatus.ChainFailed }
        else -> all
    }

    Column(Modifier.fillMaxSize().background(CanvasBg)) {
        PageHeader(title = "Drafts", subtitle = "${all.size} 条暂存")
        Spacer(Modifier.height(Spacing.tight))
        FilterChipRow(options = DraftFilters, selected = filter, onSelect = { filter = it })
        Spacer(Modifier.height(Spacing.item))

        if (drafts.isEmpty()) {
            Column(
                Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                SoundVisualCanvas(
                    seed = 1,
                    active = false,
                    modifier = Modifier
                        .size(140.dp)
                        .clip(RoundedCornerShape(Radii.collectionCard))
                        .background(Primary50),
                )
                Spacer(Modifier.height(Spacing.section))
                Text("还没有暂存的声音", color = Ink950, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(8.dp))
                Text("去捕捉此刻的声音", color = Ink600, fontSize = 14.sp)
                Spacer(Modifier.height(Spacing.section))
                Box(Modifier.width(200.dp)) {
                    PrimaryButton(text = "开始录音", onClick = onStartRecord)
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier.padding(horizontal = Spacing.pageHorizontal),
                verticalArrangement = Arrangement.spacedBy(Spacing.tight),
            ) {
                items(drafts, key = { it.id }) { item ->
                    DraftCard(
                        item = item,
                        playing = playingId == item.id,
                        onPlay = { playingId = if (playingId == item.id) null else item.id },
                        onPress = { onPress(item.id) },
                        onOpen = { onOpenDetail(item.id) },
                    )
                }
                item { Spacer(Modifier.height(Spacing.section)) }
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
    val showProgress = item.status == SoundStatus.Writing || item.status == SoundStatus.ChainPending
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(White)
            .clickable(onClick = onOpen)
            .padding(Spacing.tight),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(72.dp).clip(RoundedCornerShape(Radii.input)).background(Primary50)) {
            SoundVisualCanvas(
                seed = item.visualSeed,
                active = playing,
                showProgressRing = showProgress,
                progress = 0.65f,
                modifier = Modifier.fillMaxSize().padding(6.dp),
            )
        }
        Spacer(Modifier.width(Spacing.tight))
        Column(Modifier.weight(1f)) {
            Text(item.title, color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Spacer(Modifier.height(4.dp))
            Text(
                "${formatRecordedAt(item.recordedAtMillis)} · ${formatDuration(item.durationSec)} · ${item.category}",
                color = Ink600,
                fontSize = 12.sp,
            )
            if (item.locationLabel != "地点未记录") {
                Text(item.locationLabel, color = Ink400, fontSize = 12.sp)
            }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.chip), verticalAlignment = Alignment.CenterVertically) {
                StatusChip(item.status)
                if (item.status == SoundStatus.Drafted || item.status == SoundStatus.WriteFailed) {
                    Text(
                        "Press",
                        color = Primary500,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 13.sp,
                        modifier = Modifier.clickable(onClick = onPress),
                    )
                }
                if (item.status == SoundStatus.ChainFailed) {
                    Text("重试上链", color = Primary700, fontSize = 13.sp, modifier = Modifier.clickable(onClick = onPress))
                }
            }
        }
        Box(
            Modifier.size(36.dp).clip(CircleShape).background(Primary50).clickable(onClick = onPlay),
            contentAlignment = Alignment.Center,
        ) {
            Text(if (playing) "‖" else "▶", color = Ink950, fontSize = 12.sp)
        }
    }
}

@Composable
fun DraftDetailScreen(id: String, onBack: () -> Unit, onPress: () -> Unit, onDeleted: () -> Unit) {
    val item = SoundRepository.get(id)
    var confirmDelete by remember { mutableStateOf(false) }
    var playing by remember { mutableStateOf(false) }

    if (item == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("声音不存在", color = Ink600)
        }
    } else {
        Column(
            Modifier.fillMaxSize().background(CanvasBg).padding(Spacing.pageHorizontal),
        ) {
            Row(Modifier.fillMaxWidth().padding(vertical = Spacing.item), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("返回", color = Ink600, modifier = Modifier.clickable(onClick = onBack))
                Text("详情", color = Ink950, fontWeight = FontWeight.SemiBold)
                Text("删除", color = Ink400, modifier = Modifier.clickable { confirmDelete = true })
            }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(300.dp)
                    .clip(RoundedCornerShape(Radii.collectionCard))
                    .background(Primary50)
                    .clickable { playing = !playing },
                contentAlignment = Alignment.Center,
            ) {
                SoundVisualCanvas(
                    seed = item.visualSeed,
                    active = playing,
                    modifier = Modifier.fillMaxSize().padding(Spacing.section),
                )
            }
            Spacer(Modifier.height(Spacing.section))
            Text(item.title, color = Ink950, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            StatusChip(item.status)
            Spacer(Modifier.height(Spacing.tight))
            Text("#${item.category}", color = Ink600, fontSize = 14.sp)
            if (item.description.isNotBlank()) {
                Spacer(Modifier.height(Spacing.tight))
                Text(item.description, color = Ink600, fontSize = 15.sp, lineHeight = 24.sp)
            }
            Spacer(Modifier.height(Spacing.item))
            Text(
                "${formatRecordedAt(item.recordedAtMillis)} · ${item.locationLabel} · ${formatDuration(item.durationSec)}",
                color = Ink400,
                fontSize = 12.sp,
            )
            Spacer(Modifier.weight(1f))
            PrimaryButton(
                text = if (item.status == SoundStatus.ChainFailed) "重试上链" else "写入声片",
                onClick = onPress,
            )
            Spacer(Modifier.height(Spacing.item))
        }
    }

    if (confirmDelete && item != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("删除这段声音？") },
            text = { Text("录音、声音视觉和相关记忆信息将被永久移除。") },
            confirmButton = {
                TextButton(onClick = {
                    if (SoundRepository.delete(id)) onDeleted()
                    confirmDelete = false
                }) { Text("确认删除") }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("取消") } },
        )
    }
}
