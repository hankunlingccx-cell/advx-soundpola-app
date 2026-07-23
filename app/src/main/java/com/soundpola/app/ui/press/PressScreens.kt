package com.soundpola.app.ui.press

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.data.SoundRepository
import com.soundpola.app.data.SoundStatus
import com.soundpola.app.data.formatDuration
import com.soundpola.app.ui.components.NfcRippleVisual
import com.soundpola.app.ui.components.PrimaryButton
import com.soundpola.app.ui.components.SecondaryButton
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Line200
import com.soundpola.app.ui.theme.Primary100
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.Primary700
import com.soundpola.app.ui.theme.Radii
import com.soundpola.app.ui.theme.Spacing
import com.soundpola.app.ui.theme.Warning
import com.soundpola.app.ui.theme.White
import kotlinx.coroutines.delay

/** first.md §7.7–7.10 Press 流程 — designstyle §10.4 */
@Composable
fun PressMethodScreen(id: String, onBack: () -> Unit, onNfc: () -> Unit) {
    val item = SoundRepository.get(id) ?: return
    Column(Modifier.fillMaxSize().background(CanvasBg).padding(Spacing.pageHorizontal)) {
        TopBar("准备写入", onBack)
        Spacer(Modifier.height(Spacing.section))
        SoundHeader(item.title, item.category, item.durationSec, item.visualSeed)
        Spacer(Modifier.height(Spacing.section))
        Text("选择写入方式", color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        Spacer(Modifier.height(Spacing.tight))
        MethodCard("手机 NFC 写入", "将空白声片靠近手机背面，完成永久绑定。", "开始检测声片", onClick = onNfc)
        Spacer(Modifier.height(Spacing.tight))
        MethodCard("硬件设备写入", "连接桌面装置后写入。MVP 先使用手机 NFC。", "稍后支持", enabled = false, onClick = {})
    }
}

@Composable
fun PressDetectScreen(id: String, onBack: () -> Unit, onDetected: () -> Unit) {
    var phase by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { delay(2200); phase = 1 }

    Column(
        Modifier.fillMaxSize().background(CanvasBg).padding(Spacing.pageHorizontal),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TopBar("检测声片", onBack)
        Spacer(Modifier.weight(0.25f))
        NfcRippleVisual(active = phase == 0)
        Spacer(Modifier.height(Spacing.section))
        Text(
            text = if (phase == 0) "将手机背面靠近声片" else "发现空白声片 SP-BLANK-09",
            color = Ink950,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        Text(
            if (phase == 0) "保持贴近，不要移动" else "可以继续永久绑定确认",
            color = Ink600,
            fontSize = 14.sp,
        )
        Spacer(Modifier.weight(0.35f))
        if (phase == 1) PrimaryButton("继续", onDetected) else SecondaryButton("取消", onBack)
        Spacer(Modifier.height(Spacing.item))
    }
}

@Composable
fun PressConfirmScreen(id: String, onBack: () -> Unit, onConfirm: () -> Unit) {
    val item = SoundRepository.get(id) ?: return
    var checked by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(CanvasBg).padding(Spacing.pageHorizontal)) {
        TopBar("永久绑定", onBack)
        Spacer(Modifier.height(Spacing.section))
        SoundHeader(item.title, item.category, item.durationSec, item.visualSeed)
        Spacer(Modifier.height(Spacing.section))
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radii.card))
                .background(Primary50)
                .padding(Spacing.item),
        ) {
            Text("声片编号", color = Ink400, fontSize = 12.sp)
            Text("SP-BLANK-09", color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Spacer(Modifier.height(Spacing.tight))
            Text(
                "每张声片只能写入一个声音。写入完成后，声音和声片将永久绑定，无法替换或覆盖。",
                color = Warning,
                fontSize = 13.sp,
                lineHeight = 20.sp,
            )
        }
        Spacer(Modifier.height(Spacing.item))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked, { checked = it }, colors = CheckboxDefaults.colors(checkedColor = Primary500))
            Text("我已确认当前声音和声片", color = Ink950, fontSize = 14.sp)
        }
        Spacer(Modifier.weight(1f))
        PrimaryButton("确认并写入", enabled = checked, onClick = onConfirm)
        Spacer(Modifier.height(Spacing.tight))
        SecondaryButton("返回检查", onClick = onBack)
    }
}

@Composable
fun PressProgressScreen(id: String, onDone: () -> Unit) {
    val steps = listOf("写入声片", "校验声片", "创建数字资产", "上链确认")
    var step by remember { mutableIntStateOf(0) }
    var progress by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(Unit) {
        SoundRepository.update(id) { it.copy(status = SoundStatus.Writing) }
        for (i in steps.indices) {
            step = i
            progress = 0f
            while (progress < 1f) {
                delay(35)
                progress += 0.04f
            }
        }
        SoundRepository.markCollected(id, "SP-2026-${(10..99).random()}${(10..99).random()}", "0x${(1000..9999).random()}…${(100..999).random()}")
        onDone()
    }

    Column(
        Modifier.fillMaxSize().background(CanvasBg).padding(Spacing.pageHorizontal),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(Spacing.block))
        Text("正在压入这一刻", color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Text("请保持手机靠近声片，不要关闭 App", color = Ink600, fontSize = 13.sp)
        Spacer(Modifier.height(Spacing.block))
        SoundVisualCanvas(
            seed = SoundRepository.get(id)?.visualSeed ?: 1,
            active = true,
            modifier = Modifier
                .size(200.dp)
                .clip(RoundedCornerShape(Radii.collectionCard))
                .background(Primary50),
        )
        Spacer(Modifier.height(Spacing.block))
        Text(steps[step], color = Primary700, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        Spacer(Modifier.height(Spacing.tight))
        LinearProgressIndicator(
            progress = { progress.coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50)),
            color = Primary500,
            trackColor = Primary100,
        )
        Spacer(Modifier.height(Spacing.tight))
        Text("步骤 ${step + 1} / ${steps.size}", color = Ink400, fontSize = 12.sp)
    }
}

@Composable
fun PressDoneScreen(id: String, onCollection: () -> Unit, onMemory: () -> Unit) {
    val item = SoundRepository.get(id)
    Column(
        Modifier.fillMaxSize().background(CanvasBg).padding(Spacing.pageHorizontal),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(Spacing.block))
        Text("这段声音已经拥有实体", color = Ink950, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Spacing.section))
        SoundVisualCanvas(
            seed = item?.visualSeed ?: 1,
            active = false,
            modifier = Modifier
                .size(220.dp)
                .clip(RoundedCornerShape(Radii.collectionCard))
                .background(Primary50),
        )
        Spacer(Modifier.height(Spacing.section))
        Text(item?.title ?: "", color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        Text("声片 ${item?.discId ?: "—"}", color = Ink600, fontSize = 13.sp)
        Spacer(Modifier.weight(1f))
        PrimaryButton("查看 Memory", onClick = onMemory)
        Spacer(Modifier.height(Spacing.tight))
        SecondaryButton("前往 Collection", onClick = onCollection)
        Spacer(Modifier.height(Spacing.item))
    }
}

@Composable
private fun TopBar(title: String, onBack: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = Spacing.item), horizontalArrangement = Arrangement.SpaceBetween) {
        Text("返回", color = Ink600, modifier = Modifier.clickable(onClick = onBack))
        Text(title, color = Ink950, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.size(32.dp))
    }
}

@Composable
private fun SoundHeader(title: String, category: String, duration: Int, seed: Int) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(White)
            .border(1.dp, Line200, RoundedCornerShape(Radii.card))
            .padding(Spacing.tight),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SoundVisualCanvas(
            seed = seed,
            active = false,
            modifier = Modifier.size(56.dp).clip(RoundedCornerShape(Radii.input)).background(Primary50),
        )
        Spacer(Modifier.size(Spacing.tight))
        Column {
            Text(title, color = Ink950, fontWeight = FontWeight.SemiBold)
            Text("$category · ${formatDuration(duration)}", color = Ink600, fontSize = 12.sp)
        }
    }
}

@Composable
private fun MethodCard(title: String, body: String, action: String, enabled: Boolean = true, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(White)
            .border(1.dp, Line200, RoundedCornerShape(Radii.card))
            .padding(Spacing.item),
    ) {
        Text(title, color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        Spacer(Modifier.height(6.dp))
        Text(body, color = Ink600, fontSize = 13.sp, lineHeight = 20.sp)
        Spacer(Modifier.height(Spacing.tight))
        Text(action, color = if (enabled) Primary700 else Ink400, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable(enabled = enabled, onClick = onClick))
    }
}
