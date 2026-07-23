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
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.data.SoundStatus
import com.soundpola.app.ui.theme.CanvasBg
import com.soundpola.app.ui.theme.Error
import com.soundpola.app.ui.theme.Info
import com.soundpola.app.ui.theme.Ink400
import com.soundpola.app.ui.theme.Ink950
import com.soundpola.app.ui.theme.Line200
import com.soundpola.app.ui.theme.Primary100
import com.soundpola.app.ui.theme.Primary300
import com.soundpola.app.ui.theme.Primary50
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.Primary600
import com.soundpola.app.ui.theme.Primary700
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
            .height(54.dp)
            .clip(RoundedCornerShape(16.dp))
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
            .height(54.dp)
            .clip(RoundedCornerShape(16.dp))
            .border(1.dp, Line200, RoundedCornerShape(16.dp))
            .background(White)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = Ink950,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
        )
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
            .clip(RoundedCornerShape(50))
            .background(bg)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    ) {
        Text(text = label, color = fg, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
fun SoundVisualCanvas(
    seed: Int,
    active: Boolean,
    modifier: Modifier = Modifier,
    dark: Boolean = false,
) {
    val infinite = rememberInfiniteTransition(label = "visual")
    val breath by infinite.animateFloat(
        initialValue = 0.92f,
        targetValue = 1.08f,
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
            tween(if (active) 7000 else 20000, easing = LinearEasing),
            RepeatMode.Restart,
        ),
        label = "spin",
    )

    Canvas(modifier = modifier) {
        val cx = size.width / 2f
        val cy = size.height / 2f
        val radius = size.minDimension / 2f
        val colors = listOf(Primary500, Primary300, Primary600, Primary700)
        val baseAlpha = if (dark) 0.55f else 0.4f

        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(
                    Primary500.copy(alpha = if (active) 0.35f else 0.18f),
                    Color.Transparent,
                ),
                center = Offset(cx, cy),
                radius = radius,
            ),
            radius = radius,
            center = Offset(cx, cy),
        )

        val count = 14 + (seed % 12)
        for (i in 0 until count) {
            val angle = Math.toRadians((spin + i * (360f / count) + seed % 40).toDouble())
            val layer = 0.22f + (i % 5) * 0.1f
            val wobble = 1f + 0.12f * sin(angle * if (active) 3.0 else 1.5).toFloat()
            val r = radius * layer * breath * wobble
            val x = cx + cos(angle).toFloat() * r
            val y = cy + sin(angle).toFloat() * r
            // bilateral symmetry
            val mirrorX = cx - cos(angle).toFloat() * r
            val color = colors[i % colors.size].copy(alpha = baseAlpha)
            val dot = if (active) 4.5.dp.toPx() else 3.2.dp.toPx()
            drawCircle(color = color, radius = dot, center = Offset(x, y))
            drawCircle(color = color, radius = dot, center = Offset(mirrorX, y))
        }

        drawCircle(
            color = Primary500.copy(alpha = if (dark) 0.45f else 0.28f),
            radius = radius * 0.18f * breath,
            center = Offset(cx, cy),
            style = Stroke(width = 1.5.dp.toPx()),
        )
    }
}

@Composable
fun RecordFab(
    recording: Boolean,
    onClick: () -> Unit,
    size: Dp = 76.dp,
) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(size + 24.dp)) {
        if (recording) {
            Box(
                modifier = Modifier
                    .size(size + 18.dp)
                    .border(1.dp, Primary500.copy(alpha = 0.35f), CircleShape),
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
fun BottomNavBar(
    selected: Int,
    onSelect: (Int) -> Unit,
) {
    val labels = listOf("Record", "Drafts", "Collection")
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(72.dp)
            .background(CanvasBg.copy(alpha = 0.96f))
            .border(width = 1.dp, color = Line200.copy(alpha = 0.6f))
            .padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        labels.forEachIndexed { index, label ->
            val selectedTab = selected == index
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(if (selectedTab) Primary100 else Color.Transparent)
                    .clickable { onSelect(index) }
                    .padding(horizontal = 16.dp, vertical = 10.dp),
            ) {
                Text(
                    text = label,
                    color = if (selectedTab) Ink950 else Ink400,
                    fontSize = 13.sp,
                    fontWeight = if (selectedTab) FontWeight.SemiBold else FontWeight.Medium,
                )
            }
        }
    }
}
