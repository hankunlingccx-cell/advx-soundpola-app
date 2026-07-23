package com.soundpola.app.ui.collection

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
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
import com.soundpola.app.data.formatDuration
import com.soundpola.app.data.formatRecordedAt
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.components.StatusChip
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary700
import com.soundpola.app.ui.theme.White

@Composable
fun CollectionScreen(onOpenMemory: (String) -> Unit) {
    val items = SoundRepository.collection()
    var gridMode by remember { mutableStateOf(true) }

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
            Text("Collection", color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            Text(
                text = if (gridMode) "网格" else "时间轴",
                color = Primary700,
                fontSize = 13.sp,
                modifier = Modifier.clickable { gridMode = !gridMode },
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text("${items.size} 枚已收藏声片", color = Ink400, fontSize = 13.sp)
        Spacer(modifier = Modifier.height(16.dp))

        if (items.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("完成写入与上链后，声音会出现在这里", color = Ink600)
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(bottom = 24.dp),
            ) {
                items(items, key = { it.id }) { item ->
                    CollectionCard(item = item, onClick = { onOpenMemory(item.id) })
                }
            }
        }
    }
}

@Composable
private fun CollectionCard(item: SoundMemory, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(24.dp))
            .background(White)
            .clickable(onClick = onClick),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.85f)
                .background(Primary50),
        ) {
            SoundVisualCanvas(
                seed = item.visualSeed,
                active = false,
                modifier = Modifier.fillMaxSize().padding(12.dp),
            )
        }
        Column(modifier = Modifier.padding(12.dp)) {
            Text(item.title, color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1)
            Spacer(modifier = Modifier.height(4.dp))
            Text(formatRecordedAt(item.recordedAtMillis).take(10), color = Ink400, fontSize = 12.sp)
        }
    }
}

@Composable
fun MemoryScreen(id: String, onBack: () -> Unit) {
    val item = SoundRepository.get(id)
    var playing by remember { mutableStateOf(false) }

    if (item == null) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("声音不存在", color = Ink600)
        }
        return
    }

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
            Text("返回", color = Ink600, modifier = Modifier.clickable(onClick = onBack))
            Text("Memory", color = Ink950, fontWeight = FontWeight.SemiBold)
            Text("分享", color = Primary700)
        }
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            formatRecordedAt(item.recordedAtMillis),
            color = Ink400,
            fontSize = 12.sp,
        )
        Text(item.locationLabel, color = Ink600, fontSize = 13.sp)
        Spacer(modifier = Modifier.height(16.dp))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(320.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(Primary50)
                .clickable { playing = !playing },
            contentAlignment = Alignment.Center,
        ) {
            SoundVisualCanvas(
                seed = item.visualSeed,
                active = playing,
                modifier = Modifier.fillMaxSize().padding(20.dp),
            )
        }
        Spacer(modifier = Modifier.height(20.dp))
        Text(item.title, color = Ink950, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(8.dp))
        Text("#${item.category}  ·  ${formatDuration(item.durationSec)}", color = Ink600, fontSize = 14.sp)
        Spacer(modifier = Modifier.height(8.dp))
        StatusChip(item.status)
        if (item.description.isNotBlank()) {
            Spacer(modifier = Modifier.height(16.dp))
            Text(item.description, color = Ink600, fontSize = 15.sp, lineHeight = 24.sp)
        }
        Spacer(modifier = Modifier.height(24.dp))
        InfoRow("声片编号", item.discId ?: "—")
        InfoRow("数字资产", item.assetId ?: "—")
        InfoRow("录制设备", item.deviceLabel)
        InfoRow("绑定状态", "永久绑定")
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, color = Ink400, fontSize = 13.sp)
        Text(value, color = Ink950, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}
