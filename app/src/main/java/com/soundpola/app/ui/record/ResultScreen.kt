package com.soundpola.app.ui.record

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
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
import com.soundpola.app.ui.components.SectionLabel
import com.soundpola.app.ui.components.SoundVisualCanvas
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.ComponentSize
import com.soundpola.app.ui.theme.Error
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Primary100
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary700
import com.soundpola.app.ui.theme.Radii
import com.soundpola.app.ui.theme.Spacing
import com.soundpola.app.ui.theme.Surface100

/** first.md §7.4 录音结果页 — designstyle §10.2 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ResultScreen(durationSec: Int, onSaved: () -> Unit, onReRecord: () -> Unit) {
    var title by remember { mutableStateOf("未命名声音") }
    var category by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var playing by remember { mutableStateOf(false) }
    var titleError by remember { mutableStateOf(false) }
    var categoryError by remember { mutableStateOf(false) }
    val recordedAt = remember { System.currentTimeMillis() }
    val seed = remember { (1000..9999).random() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .verticalScroll(rememberScrollState())
            .padding(Spacing.pageHorizontal),
    ) {
        Spacer(Modifier.height(Spacing.item))
        Text("录音结果", color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(Spacing.item))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(260.dp)
                .clip(RoundedCornerShape(Radii.collectionCard))
                .background(Primary50)
                .clickable { playing = !playing },
            contentAlignment = Alignment.Center,
        ) {
            SoundVisualCanvas(
                seed = seed,
                active = playing,
                modifier = Modifier.fillMaxSize().padding(Spacing.item),
            )
        }

        Spacer(Modifier.height(Spacing.tight))
        RowMeta(
            "${formatRecordedAt(recordedAt)} · ${formatDuration(durationSec)} · 地点未记录",
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = if (playing) "播放中…" else "点击视觉试听",
            color = Ink400,
            fontSize = 12.sp,
        )

        Spacer(Modifier.height(Spacing.section))
        SectionLabel("声音名称")
        InputField(value = title, onChange = { title = it; titleError = false }, isError = titleError)
        if (titleError) ErrorHint("请填写声音名称")

        Spacer(Modifier.height(Spacing.item))
        SectionLabel("分类")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.chip), verticalArrangement = Arrangement.spacedBy(Spacing.chip)) {
            SoundCategories.forEach { item ->
                val selected = category == item
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(if (selected) Primary100 else Surface100)
                        .border(if (selected) 1.dp else 0.dp, if (selected) Primary500 else Surface100, RoundedCornerShape(50))
                        .clickable { category = item; categoryError = false }
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                ) {
                    Text(item, color = if (selected) Primary700 else Ink600, fontSize = 13.sp)
                }
            }
        }
        if (categoryError) ErrorHint("请选择一个分类")

        Spacer(Modifier.height(Spacing.item))
        SectionLabel("描述（可选）")
        InputField(
            value = description,
            onChange = { description = it },
            minLines = 3,
            placeholder = "记录这段声音背后的故事……",
        )

        Spacer(Modifier.height(Spacing.section))
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
        Spacer(Modifier.height(Spacing.tight))
        SecondaryButton(text = "重新录制", onClick = onReRecord)
        Spacer(Modifier.height(Spacing.section))
    }
}

@Composable
private fun RowMeta(text: String) {
    Text(text, color = Ink600, fontSize = 12.sp)
}

@Composable
private fun ErrorHint(text: String) {
    Text(text, color = Error, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
}

@Composable
private fun InputField(
    value: String,
    onChange: (String) -> Unit,
    isError: Boolean = false,
    minLines: Int = 1,
    placeholder: String = "",
) {
    val height = if (minLines > 1) (ComponentSize.inputHeight.value * 1.8f).dp else ComponentSize.inputHeight
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(Radii.input))
            .background(Surface100)
            .border(if (isError) 1.5.dp else 0.dp, if (isError) Error else Surface100, RoundedCornerShape(Radii.input))
            .padding(horizontal = 14.dp, vertical = 14.dp),
    ) {
        if (value.isEmpty() && placeholder.isNotEmpty()) {
            Text(placeholder, color = Ink400, fontSize = 15.sp)
        }
        BasicTextField(
            value = value,
            onValueChange = onChange,
            textStyle = TextStyle(color = Ink950, fontSize = 15.sp),
            cursorBrush = SolidColor(Primary500),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
