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
import com.soundpola.app.ui.components.MetaRow
import com.soundpola.app.ui.components.PageHeader
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.components.StatusChip
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary700
import com.soundpola.app.ui.theme.Radii
import com.soundpola.app.ui.theme.Spacing
import com.soundpola.app.ui.theme.White

/** first.md §7 + Collection 网格 — designstyle §10.5 */
@Composable
fun CollectionScreen(onOpenMemory: (String) -> Unit) {
    val items = SoundRepository.collection()

    Column(Modifier.fillMaxSize().background(CanvasBg)) {
        PageHeader(title = "Collection", subtitle = "${items.size} 枚已收藏声片")

        if (items.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("完成写入与上链后", color = Ink600, fontSize = 15.sp)
                    Text("声音会出现在这里", color = Ink400, fontSize = 13.sp)
                }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                contentPadding = PaddingValues(horizontal = Spacing.pageHorizontal, vertical = Spacing.tight),
                horizontalArrangement = Arrangement.spacedBy(Spacing.tight),
                verticalArrangement = Arrangement.spacedBy(Spacing.tight),
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
            .clip(RoundedCornerShape(Radii.collectionCard))
            .background(White)
            .clickable(onClick = onClick),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.82f)
                .background(Primary50),
        ) {
            SoundVisualCanvas(
                seed = item.visualSeed,
                active = false,
                modifier = Modifier.fillMaxSize().padding(Spacing.tight),
            )
        }
        Column(Modifier.padding(Spacing.tight)) {
            Text(item.title, color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, maxLines = 1)
            Spacer(Modifier.height(4.dp))
            Text(formatRecordedAt(item.recordedAtMillis).take(10), color = Ink400, fontSize = 12.sp)
        }
    }
}

/** first.md Memory 回声详情 — designstyle §10.6，资产信息默认折叠 */
@Composable
fun MemoryScreen(id: String, onBack: () -> Unit) {
    val item = SoundRepository.get(id)
    var playing by remember { mutableStateOf(false) }
    var assetExpanded by remember { mutableStateOf(false) }

    if (item == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("声音不存在", color = Ink600)
        }
        return
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(Spacing.pageHorizontal),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(vertical = Spacing.item),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("返回", color = Ink600, modifier = Modifier.clickable(onClick = onBack))
            Text("Memory", color = Ink950, fontWeight = FontWeight.SemiBold)
            Text("分享", color = Primary700, fontSize = 13.sp)
        }

        Text(formatRecordedAt(item.recordedAtMillis), color = Ink400, fontSize = 12.sp)
        Text(item.locationLabel, color = Ink600, fontSize = 13.sp)
        Spacer(Modifier.height(Spacing.item))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(340.dp)
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
        Text(item.title, color = Ink950, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text("#${item.category}  ·  ${formatDuration(item.durationSec)}", color = Ink600, fontSize = 14.sp)
        Spacer(Modifier.height(8.dp))
        StatusChip(item.status)

        if (item.description.isNotBlank()) {
            Spacer(Modifier.height(Spacing.item))
            Text(item.description, color = Ink600, fontSize = 15.sp, lineHeight = 24.sp)
        }

        Spacer(Modifier.height(Spacing.section))
        Row(
            Modifier
                .fillMaxWidth()
                .clickable { assetExpanded = !assetExpanded }
                .padding(vertical = Spacing.tight),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("声片与数字资产", color = Ink950, fontWeight = FontWeight.Medium)
            Text(if (assetExpanded) "收起" else "展开", color = Primary700, fontSize = 13.sp)
        }

        if (assetExpanded) {
            MetaRow("声片编号", item.discId ?: "—")
            MetaRow("数字资产", item.assetId ?: "—")
            MetaRow("录制设备", item.deviceLabel)
            MetaRow("绑定状态", "永久绑定")
        }

        Spacer(Modifier.weight(1f))
    }
}
