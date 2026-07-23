package com.soundpola.app.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.data.SoundStatus
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.ComponentSize
import com.soundpola.app.ui.theme.Error
import com.soundpola.app.ui.theme.Info
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink600
import com.soundpola.app.ui.theme.Ink800
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Line200
import com.soundpola.app.ui.theme.Primary100
import com.soundpola.app.ui.theme.Primary300
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.Primary600
import com.soundpola.app.ui.theme.Primary700
import com.soundpola.app.ui.theme.Radii
import com.soundpola.app.ui.theme.Spacing
import com.soundpola.app.ui.theme.Surface100
import com.soundpola.app.ui.theme.White
import kotlin.math.cos
import kotlin.math.sin

@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(ComponentSize.buttonHeight)
            .clip(RoundedCornerShape(Radii.button))
            .background(if (enabled) Primary500 else Surface100)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = if (enabled) Ink950 else Ink400,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
fun SecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(ComponentSize.buttonHeight)
            .clip(RoundedCornerShape(Radii.button))
            .border(1.dp, Line200, RoundedCornerShape(Radii.button))
            .background(White)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = text, color = Ink950, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun StatusChip(status: SoundStatus) {
    val (label, bg, fg) = when (status) {
        SoundStatus.Drafted -> Triple("已暂存", Surface100, Ink950)
        SoundStatus.Writing, SoundStatus.ChainPending -> Triple("处理中", Color(0xFFE8F0FE), Info)
        SoundStatus.WriteFailed, SoundStatus.ChainFailed -> Triple("失败", Color(0xFFFDECEC), Error)
        SoundStatus.Collected -> Triple("已收藏", Primary100, Primary700)
    }
    Box(
        modifier = Modifier
            .height(ComponentSize.statusChipHeight)
            .clip(RoundedCornerShape(50))
            .background(bg)
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = label, color = fg, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
fun PageHeader(title: String, subtitle: String? = null, trailing: @Composable (() -> Unit)? = null) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.pageHorizontal, vertical = Spacing.item),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column {
            Text(text = title, color = Ink950, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            if (subtitle != null) {
                Spacer(Modifier.height(4.dp))
                Text(text = subtitle, color = Ink400, fontSize = 13.sp)
            }
        }
        trailing?.invoke()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FilterChipRow(
    options: List<String>,
    selected: String,
    onSelect: (String) -> Unit,
) {
    FlowRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.pageHorizontal),
        horizontalArrangement = Arrangement.spacedBy(Spacing.chip),
        verticalArrangement = Arrangement.spacedBy(Spacing.chip),
    ) {
        options.forEach { option ->
            val active = option == selected
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(if (active) Primary100 else Surface100)
                    .border(
                        width = if (active) 1.dp else 0.dp,
                        color = if (active) Primary500 else Surface100,
                        shape = RoundedCornerShape(50),
                    )
                    .clickable { onSelect(option) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            ) {
                Text(
                    text = option,
                    color = if (active) Primary700 else Ink600,
                    fontSize = 13.sp,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}

@Composable
fun SoundVisualCanvas(
    seed: Int,
    active: Boolean,
    modifier: Modifier = Modifier,
    dark: Boolean = false,
    showProgressRing: Boolean = false,
    progress: Float = 0f,
) {
    val infinite = rememberInfiniteTransition(label = "visual")
    val breath by infinite.animateFloat(
        initialValue = 0.94f,
        targetValue = 1.06f,
        animationSpec = infiniteRepeatable(
            tween(if (active) 900 else 2600, easing = LinearEasing),
            RepeatMode.Reverse,
        ),
        label = "breath",
    )
    val spin by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            tween(if (active) 6500 else 18000, easing = LinearEasing),
            RepeatMode.Restart,
        ),
        label = "spin",
    )

    Canvas(modifier = modifier) {
        val cx = size.width / 2f
        val cy = size.height / 2f
        val radius = size.minDimension / 2f
        val palette = listOf(Primary500, Primary300, Primary600, Primary700)
        val alpha = if (dark) 0.55f else 0.42f

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    Primary500.copy(alpha = if (active) 0.32f else 0.16f),
                    Color.Transparent,
                ),
                center = Offset(cx, cy),
                radius = radius,
            ),
            radius = radius,
            center = Offset(cx, cy),
        )

        val count = 16 + (seed % 10)
        for (i in 0 until count) {
            val angle = Math.toRadians((spin + i * (360f / count) + seed % 40).toDouble())
            val layer = 0.2f + (i % 5) * 0.11f
            val wobble = 1f + 0.1f * sin(angle * if (active) 3.0 else 1.5).toFloat()
            val r = radius * layer * breath * wobble
            val x = cx + cos(angle).toFloat() * r
            val y = cy + sin(angle).toFloat() * r
            val mirrorX = cx - cos(angle).toFloat() * r
            val color = palette[i % palette.size].copy(alpha = alpha)
            val dot = if (active) 4.2.dp.toPx() else 3.dp.toPx()
            drawCircle(color = color, radius = dot, center = Offset(x, y))
            drawCircle(color = color, radius = dot, center = Offset(mirrorX, y))
        }

        drawCircle(
            color = Primary500.copy(alpha = if (dark) 0.4f else 0.25f),
            radius = radius * 0.16f * breath,
            center = Offset(cx, cy),
            style = Stroke(width = 1.5.dp.toPx()),
        )

        if (showProgressRing) {
            drawArc(
                color = Primary500,
                startAngle = -90f,
                sweepAngle = 360f * progress.coerceIn(0f, 1f),
                useCenter = false,
                topLeft = Offset(cx - radius * 0.92f, cy - radius * 0.92f),
                size = androidx.compose.ui.geometry.Size(radius * 1.84f, radius * 1.84f),
                style = Stroke(width = 2.dp.toPx()),
            )
        }
    }
}

@Composable
fun RecordFab(
    recording: Boolean,
    onClick: () -> Unit,
    size: Dp = ComponentSize.recordButton,
) {
    val infinite = rememberInfiniteTransition(label = "recordRipple")
    val ripple by infinite.animateFloat(
        initialValue = 0.85f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(tween(1400), RepeatMode.Reverse),
        label = "ripple",
    )

    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(size + 28.dp)) {
        if (recording) {
            Box(
                modifier = Modifier
                    .size((size.value * ripple).dp)
                    .border(1.dp, Primary500.copy(alpha = 0.25f), CircleShape),
            )
            Box(
                modifier = Modifier
                    .size((size.value * (ripple - 0.08f)).dp)
                    .border(1.dp, Primary500.copy(alpha = 0.15f), CircleShape),
            )
        }
        Box(
            modifier = Modifier
                .size(size)
                .clip(CircleShape)
                .background(Primary500)
                .clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() },
                    onClick = onClick,
                ),
            contentAlignment = Alignment.Center,
        ) {
            if (recording) {
                Box(
                    modifier = Modifier
                        .size(22.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(Ink950),
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(18.dp)
                        .clip(CircleShape)
                        .background(Ink950),
                )
            }
        }
    }
}

@Composable
fun BottomNavBar(selected: Int, onSelect: (Int) -> Unit) {
    val tabs = listOf("Record" to "录音", "Drafts" to "暂存", "Collection" to "收藏")
    Column {
        HorizontalDivider(color = Line200.copy(alpha = 0.7f))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(ComponentSize.bottomNav)
                .background(CanvasBg.copy(alpha = 0.96f))
                .padding(horizontal = Spacing.pageHorizontal),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            tabs.forEachIndexed { index, (en, _) ->
                val active = selected == index
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(if (active) Primary100 else Color.Transparent)
                        .clickable { onSelect(index) }
                        .padding(horizontal = 18.dp, vertical = 10.dp),
                ) {
                    Text(
                        text = en,
                        color = if (active) Ink950 else Ink400,
                        fontSize = 13.sp,
                        fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                    )
                }
            }
        }
    }
}

@Composable
fun TimerText(seconds: Int, dark: Boolean = false) {
    Text(
        text = "%d:%02d".format(seconds / 60, seconds % 60),
        color = if (dark) White else Ink950,
        fontSize = 40.sp,
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Medium,
    )
}

@Composable
fun NfcRippleVisual(active: Boolean) {
    val infinite = rememberInfiniteTransition(label = "nfc")
    val pulse by infinite.animateFloat(
        initialValue = 0.7f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1200), RepeatMode.Reverse),
        label = "pulse",
    )
    Canvas(modifier = Modifier.size(180.dp)) {
        val cx = size.width / 2f
        val cy = size.height / 2f
        for (i in 1..3) {
            val r = size.minDimension * 0.22f * i * (if (active) pulse else 0.95f)
            drawCircle(
                color = Primary500.copy(alpha = 0.18f / i),
                radius = r,
                center = Offset(cx, cy),
                style = Stroke(width = 1.5.dp.toPx()),
            )
        }
        drawCircle(color = Primary500.copy(alpha = 0.35f), radius = 18.dp.toPx(), center = Offset(cx, cy))
    }
}

@Composable
fun SectionLabel(text: String) {
    Text(
        text = text,
        color = Ink950,
        fontSize = 14.sp,
        fontWeight = FontWeight.Medium,
        modifier = Modifier.padding(bottom = 8.dp),
    )
}

@Composable
fun MetaRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, color = Ink400, fontSize = 13.sp)
        Text(value, color = Ink800, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}
