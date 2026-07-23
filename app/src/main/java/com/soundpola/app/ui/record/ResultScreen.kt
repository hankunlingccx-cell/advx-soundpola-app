package com.soundpola.app.ui.record

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.data.SoundCategories
import com.soundpola.app.data.SoundMemory
import com.soundpola.app.data.SoundRepository
import com.soundpola.app.data.formatDuration
import com.soundpola.app.data.formatRecordedAt
import com.soundpola.app.ui.components.PrimaryButton
import com.soundpola.app.ui.components.SecondaryButton
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Error
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Line200
import com.soundpola.app.ui.theme.Primary100
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary700
import com.soundpola.app.ui.theme.Surface100
import com.soundpola.app.ui.theme.White

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ResultScreen(
    durationSec: Int,
    onSaved: () -> Unit,
    onReRecord: () -> Unit,
) {
    var title by remember { mutableStateOf("未命名声音") }
    var category by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var titleError by remember { mutableStateOf(false) }
    var categoryError by remember { mutableStateOf(false) }
    val recordedAt = remember { System.currentTimeMillis() }
    val seed = remember { (1000..9999).random() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
    ) {
        Text("录音结果", color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(16.dp))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(240.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(Primary50),
            contentAlignment = Alignment.Center,
        ) {
            SoundVisualCanvas(seed = seed, active = false, modifier = Modifier.fillMaxSize().padding(16.dp))
        }

        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "${formatRecordedAt(recordedAt)}  ·  ${formatDuration(durationSec)}  ·  地点未记录",
            color = Ink600,
            fontSize = 12.sp,
        )

        Spacer(modifier = Modifier.height(20.dp))
        FieldLabel("声音名称")
        InputBox(
            value = title,
            onValueChange = {
                title = it
                titleError = false
            },
            isError = titleError,
        )
        if (titleError) Hint("请填写声音名称", error = true)

        Spacer(modifier = Modifier.height(16.dp))
        FieldLabel("分类")
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SoundCategories.forEach { item ->
                val selected = category == item
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(if (selected) Primary100 else Surface100)
                        .border(
                            width = if (selected) 1.dp else 0.dp,
                            color = if (selected) Primary500 else Surface100,
                            shape = RoundedCornerShape(50),
                        )
                        .clickable {
                            category = item
                            categoryError = false
                        }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                ) {
                    Text(
                        text = item,
                        color = if (selected) Primary700 else Ink600,
                        fontSize = 13.sp,
                    )
                }
            }
        }
        if (categoryError) Hint("请选择一个分类", error = true)

        Spacer(modifier = Modifier.height(16.dp))
        FieldLabel("描述（可选）")
        InputBox(
            value = description,
            onValueChange = { description = it },
            singleLine = false,
            minHeight = 96.dp,
            placeholder = "记录这段声音背后的故事……",
        )

        Spacer(modifier = Modifier.height(28.dp))
        PrimaryButton(
            text = "保存至 Drafts",
            onClick = {
                titleError = title.isBlank()
                categoryError = category.isBlank()
                if (titleError || categoryError) return@PrimaryButton
                SoundRepository.addDraft(
                    SoundMemory(
                        title = title.trim(),
                        category = category,
                        description = description.trim(),
                        durationSec = durationSec,
                        recordedAtMillis = recordedAt,
                        visualSeed = seed,
                    ),
                )
                onSaved()
            },
        )
        Spacer(modifier = Modifier.height(10.dp))
        SecondaryButton(text = "重新录制", onClick = onReRecord)
        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
private fun FieldLabel(text: String) {
    Text(
        text = text,
        color = Ink950,
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        modifier = Modifier.padding(bottom = 8.dp),
    )
}

@Composable
private fun Hint(text: String, error: Boolean = false) {
    Text(
        text = text,
        color = if (error) Error else Ink400,
        fontSize = 12.sp,
        modifier = Modifier.padding(top = 6.dp),
    )
}

@Composable
private fun InputBox(
    value: String,
    onValueChange: (String) -> Unit,
    isError: Boolean = false,
    singleLine: Boolean = true,
    minHeight: androidx.compose.ui.unit.Dp = 52.dp,
    placeholder: String = "",
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(minHeight)
            .clip(RoundedCornerShape(14.dp))
            .background(Surface100)
            .border(
                width = if (isError) 1.5.dp else 0.dp,
                color = if (isError) Error else Line200,
                shape = RoundedCornerShape(14.dp),
            )
            .padding(horizontal = 14.dp, vertical = 14.dp),
    ) {
        if (value.isEmpty() && placeholder.isNotEmpty()) {
            Text(placeholder, color = Ink400, fontSize = 15.sp)
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = singleLine,
            textStyle = TextStyle(color = Ink950, fontSize = 15.sp),
            cursorBrush = SolidColor(Primary500),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
