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
import androidx.compose.foundation.shape.CircleShape
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
import com.soundpola.app.ui.theme.Warning
import com.soundpola.app.ui.theme.White
import kotlinx.coroutines.delay

@Composable
fun PressMethodScreen(id: String, onBack: () -> Unit, onNfc: () -> Unit) {
    val item = SoundRepository.get(id) ?: return
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(20.dp),
    ) {
        TopBar(title = "准备写入", onBack = onBack)
        Spacer(modifier = Modifier.height(20.dp))
        SoundHeader(item.title, item.category, item.durationSec, item.visualSeed)
        Spacer(modifier = Modifier.height(24.dp))
        Text("选择写入方式", color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        Spacer(modifier = Modifier.height(12.dp))
        MethodCard(
            title = "手机 NFC 写入",
            body = "将空白声片靠近手机背面，完成永久绑定。",
            action = "开始检测声片",
            onClick = onNfc,
        )
        Spacer(modifier = Modifier.height(12.dp))
        MethodCard(
            title = "硬件设备写入",
            body = "连接桌面装置后写入。MVP 先使用手机 NFC。",
            action = "稍后支持",
            enabled = false,
            onClick = {},
        )
    }
}

@Composable
fun PressDetectScreen(id: String, onBack: () -> Unit, onDetected: () -> Unit) {
    var phase by remember { mutableIntStateOf(0) } // 0 searching, 1 found
    LaunchedEffect(Unit) {
        delay(2200)
        phase = 1
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TopBar(title = "检测声片", onBack = onBack)
        Spacer(modifier = Modifier.weight(0.3f))
        Box(
            modifier = Modifier
                .size(180.dp)
                .clip(CircleShape)
                .background(Primary50)
                .border(2.dp, Primary500.copy(alpha = 0.4f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(if (phase == 0) "搜索中" else "已发现", color = Primary700, fontWeight = FontWeight.SemiBold)
        }
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = if (phase == 0) "将手机背面靠近声片" else "发现空白声片 SP-BLANK-09",
            color = Ink950,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = if (phase == 0) "保持贴近，不要移动" else "可以继续永久绑定确认",
            color = Ink600,
            fontSize = 14.sp,
        )
        Spacer(modifier = Modifier.weight(0.4f))
        if (phase == 1) {
            PrimaryButton(text = "继续", onClick = onDetected)
        } else {
            SecondaryButton(text = "取消", onClick = onBack)
        }
        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
fun PressConfirmScreen(id: String, onBack: () -> Unit, onConfirm: () -> Unit) {
    val item = SoundRepository.get(id) ?: return
    var checked by remember { mutableStateOf(false) }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(20.dp),
    ) {
        TopBar(title = "永久绑定", onBack = onBack)
        Spacer(modifier = Modifier.height(20.dp))
        SoundHeader(item.title, item.category, item.durationSec, item.visualSeed)
        Spacer(modifier = Modifier.height(20.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(18.dp))
                .background(Primary50)
                .padding(16.dp),
        ) {
            Column {
                Text("声片编号", color = Ink400, fontSize = 12.sp)
                Text("SP-BLANK-09", color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    "每张声片只能写入一个声音。写入完成后，声音和声片将永久绑定，无法替换或覆盖。",
                    color = Warning,
                    fontSize = 13.sp,
                    lineHeight = 20.sp,
                )
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(
                checked = checked,
                onCheckedChange = { checked = it },
                colors = CheckboxDefaults.colors(checkedColor = Primary500),
            )
            Text("我已确认当前声音和声片", color = Ink950, fontSize = 14.sp)
        }
        Spacer(modifier = Modifier.weight(1f))
        PrimaryButton(text = "确认并写入", enabled = checked, onClick = onConfirm)
        Spacer(modifier = Modifier.height(10.dp))
        SecondaryButton(text = "返回检查", onClick = onBack)
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
                delay(40)
                progress += 0.04f
            }
        }
        val disc = "SP-2026-${(10..99).random()}${(10..99).random()}"
        val asset = "0x${(1000..9999).random()}…${(100..999).random()}"
        SoundRepository.markCollected(id, disc, asset)
        onDone()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(40.dp))
        Text("正在压入这一刻", color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(8.dp))
        Text("请保持手机靠近声片，不要关闭 App", color = Ink600, fontSize = 13.sp)
        Spacer(modifier = Modifier.height(32.dp))
        SoundVisualCanvas(
            seed = SoundRepository.get(id)?.visualSeed ?: 1,
            active = true,
            modifier = Modifier
                .size(200.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(Primary50),
        )
        Spacer(modifier = Modifier.height(32.dp))
        Text(steps[step], color = Primary700, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        Spacer(modifier = Modifier.height(12.dp))
        LinearProgressIndicator(
            progress = { progress.coerceIn(0f, 1f) },
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(50)),
            color = Primary500,
            trackColor = Primary100,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text("步骤 ${step + 1} / ${steps.size}", color = Ink400, fontSize = 12.sp)
    }
}

@Composable
fun PressDoneScreen(id: String, onCollection: () -> Unit, onMemory: () -> Unit) {
    val item = SoundRepository.get(id)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(48.dp))
        Text("这段声音已经拥有实体", color = Ink950, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Spacer(modifier = Modifier.height(24.dp))
        SoundVisualCanvas(
            seed = item?.visualSeed ?: 1,
            active = false,
            modifier = Modifier
                .size(220.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(Primary50),
        )
        Spacer(modifier = Modifier.height(20.dp))
        Text(item?.title ?: "", color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        Spacer(modifier = Modifier.height(8.dp))
        Text("声片 ${item?.discId ?: "—"}", color = Ink600, fontSize = 13.sp)
        Text("资产 ${item?.assetId ?: "—"}", color = Ink600, fontSize = 13.sp)
        Spacer(modifier = Modifier.weight(1f))
        PrimaryButton(text = "查看 Memory", onClick = onMemory)
        Spacer(modifier = Modifier.height(10.dp))
        SecondaryButton(text = "前往 Collection", onClick = onCollection)
        Spacer(modifier = Modifier.height(16.dp))
    }
}

@Composable
private fun TopBar(title: String, onBack: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text("返回", color = Ink600, modifier = Modifier.clickable(onClick = onBack))
        Text(title, color = Ink950, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.size(32.dp))
    }
}

@Composable
private fun SoundHeader(title: String, category: String, duration: Int, seed: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(White)
            .border(1.dp, Line200, RoundedCornerShape(18.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SoundVisualCanvas(
            seed = seed,
            active = false,
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Primary50),
        )
        Spacer(modifier = Modifier.size(12.dp))
        Column {
            Text(title, color = Ink950, fontWeight = FontWeight.SemiBold)
            Text("$category · ${formatDuration(duration)}", color = Ink600, fontSize = 12.sp)
        }
    }
}

@Composable
private fun MethodCard(
    title: String,
    body: String,
    action: String,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(if (enabled) White else White.copy(alpha = 0.7f))
            .border(1.dp, Line200, RoundedCornerShape(18.dp))
            .padding(16.dp),
    ) {
        Text(title, color = Ink950, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
        Spacer(modifier = Modifier.height(6.dp))
        Text(body, color = Ink600, fontSize = 13.sp, lineHeight = 20.sp)
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = action,
            color = if (enabled) Primary700 else Ink400,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.clickable(enabled = enabled, onClick = onClick),
        )
    }
}
