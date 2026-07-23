package com.soundpola.app.ui.home

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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.soundpola.app.ui.theme.Accent
import com.soundpola.app.ui.theme.Black
import com.soundpola.app.ui.theme.InputBackground
import com.soundpola.app.ui.theme.SoundpolaTheme
import com.soundpola.app.ui.theme.White
import kotlin.math.cos
import kotlin.math.sin

/** Demo palette matching Figma track capsules */
private val DiscMint = Color(0xFF63E0CB)
private val DiscSky = Color(0xFF91D5FF)
private val DiscPink = Color(0xFFEEA7F9)
private val DiscAmber = Color(0xFFD7B068)

data class SoundDisc(
    val id: String,
    val color: Color,
)

data class TrackCapsule(
    val id: String,
    val label: String,
    val discs: List<SoundDisc>,
)

private val SampleTracks = listOf(
    TrackCapsule(
        id = "people",
        label = "人的声音",
        discs = listOf(
            SoundDisc("p1", DiscMint),
            SoundDisc("p2", DiscSky),
            SoundDisc("p3", DiscPink),
            SoundDisc("p4", DiscAmber),
        ),
    ),
    TrackCapsule(
        id = "music",
        label = "音乐与现场",
        discs = listOf(
            SoundDisc("m1", DiscMint),
            SoundDisc("m2", DiscSky),
            SoundDisc("m3", DiscSky),
            SoundDisc("m4", DiscSky),
            SoundDisc("m5", DiscPink),
            SoundDisc("m6", DiscAmber),
        ),
    ),
    TrackCapsule(
        id = "nature",
        label = "自然与远方",
        discs = listOf(
            SoundDisc("n1", DiscMint),
            SoundDisc("n2", DiscSky),
            SoundDisc("n3", DiscPink),
            SoundDisc("n4", DiscAmber),
        ),
    ),
    TrackCapsule(
        id = "daily",
        label = "日常碎片",
        discs = listOf(
            SoundDisc("d1", DiscAmber),
            SoundDisc("d2", DiscPink),
            SoundDisc("d3", DiscMint),
        ),
    ),
)

/**
 * Home — Gallery + Track Capsules + Sound Stage + Record button.
 * Structure locked by product IA (first.md §三).
 * Visual reference: Figma node 65:293
 */
@Composable
fun HomeScreen(
    tracks: List<TrackCapsule> = SampleTracks,
    onGalleryClick: () -> Unit = {},
    onTrackClick: (TrackCapsule) -> Unit = {},
    onDiscClick: (SoundDisc) -> Unit = {},
    onRecordToggle: (recording: Boolean) -> Unit = {},
) {
    var recording by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Black),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            HomeTopBar()

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = "Gallery",
                color = White,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .padding(horizontal = 20.dp)
                    .clickable(
                        indication = null,
                        interactionSource = remember { MutableInteractionSource() },
                        onClick = onGalleryClick,
                    ),
            )

            Spacer(modifier = Modifier.height(16.dp))

            GalleryTrackRow(
                tracks = tracks,
                onTrackClick = onTrackClick,
                onDiscClick = onDiscClick,
            )

            Spacer(modifier = Modifier.weight(1f))

            SoundStage(
                recording = recording,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            )

            Spacer(modifier = Modifier.weight(1f))

            RecordButton(
                recording = recording,
                onClick = {
                    recording = !recording
                    onRecordToggle(recording)
                },
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(bottom = 28.dp),
            )
        }
    }
}

@Composable
private fun HomeTopBar() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "SoundPola",
            color = White.copy(alpha = 0.9f),
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )
        Box(
            modifier = Modifier
                .size(32.dp)
                .border(1.dp, White.copy(alpha = 0.25f), CircleShape)
                .clip(CircleShape)
                .background(InputBackground),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "我",
                color = White.copy(alpha = 0.7f),
                fontSize = 12.sp,
            )
        }
    }
}

@Composable
private fun GalleryTrackRow(
    tracks: List<TrackCapsule>,
    onTrackClick: (TrackCapsule) -> Unit,
    onDiscClick: (SoundDisc) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        tracks.forEach { track ->
            TrackCapsuleCard(
                track = track,
                onTrackClick = { onTrackClick(track) },
                onDiscClick = onDiscClick,
            )
        }
    }
}

@Composable
private fun TrackCapsuleCard(
    track: TrackCapsule,
    onTrackClick: () -> Unit,
    onDiscClick: (SoundDisc) -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.clickable(
            indication = null,
            interactionSource = remember { MutableInteractionSource() },
            onClick = onTrackClick,
        ),
    ) {
        Row(
            modifier = Modifier
                .height(120.dp)
                .border(1.dp, White.copy(alpha = 0.13f), RoundedCornerShape(400.dp))
                .background(InputBackground, RoundedCornerShape(400.dp))
                .padding(horizontal = 10.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy((-18).dp),
        ) {
            track.discs.forEach { disc ->
                SoundDiscChip(
                    disc = disc,
                    size = 100.dp,
                    onClick = { onDiscClick(disc) },
                )
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = track.label,
            color = White.copy(alpha = 0.55f),
            fontSize = 12.sp,
        )
    }
}

@Composable
private fun SoundDiscChip(
    disc: SoundDisc,
    size: Dp,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(size)
            .shadow(4.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.25f))
            .clip(CircleShape)
            .background(
                brush = Brush.radialGradient(
                    colors = listOf(
                        disc.color.copy(alpha = 0.95f),
                        disc.color.copy(alpha = 0.65f),
                        disc.color.copy(alpha = 0.85f),
                    ),
                ),
            )
            .border(1.dp, White.copy(alpha = 0.18f), CircleShape)
            .clickable(
                indication = null,
                interactionSource = remember { MutableInteractionSource() },
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        // vinyl-like inner ring
        Box(
            modifier = Modifier
                .size(size * 0.28f)
                .border(1.dp, Black.copy(alpha = 0.25f), CircleShape)
                .background(Black.copy(alpha = 0.2f), CircleShape),
        )
    }
}

@Composable
private fun SoundStage(
    recording: Boolean,
    modifier: Modifier = Modifier,
) {
    val infinite = rememberInfiniteTransition(label = "soundStage")
    val breath by infinite.animateFloat(
        initialValue = 0.92f,
        targetValue = 1.08f,
        animationSpec = infiniteRepeatable(
            animation = tween(if (recording) 900 else 2400, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "breath",
    )
    val spin by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(if (recording) 6000 else 18000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "spin",
    )

    Box(
        modifier = modifier.size(302.dp),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val cx = size.width / 2f
            val cy = size.height / 2f
            val radius = size.minDimension / 2f

            drawCircle(
                color = Accent.copy(alpha = if (recording) 0.55f else 0.35f),
                radius = radius * breath * 0.98f,
                center = Offset(cx, cy),
                style = Stroke(width = 1.5.dp.toPx()),
            )
            drawCircle(
                color = Accent.copy(alpha = 0.12f),
                radius = radius * breath * 0.78f,
                center = Offset(cx, cy),
                style = Stroke(width = 1.dp.toPx()),
            )

            val particleCount = if (recording) 36 else 18
            val base = radius * (if (recording) 0.42f else 0.28f) * breath
            for (i in 0 until particleCount) {
                val angle = Math.toRadians((spin + i * (360f / particleCount)).toDouble())
                val wobble = if (recording) {
                    1f + 0.18f * sin(angle * 3).toFloat()
                } else {
                    1f + 0.06f * sin(angle * 2).toFloat()
                }
                val r = base * wobble
                val x = cx + cos(angle).toFloat() * r
                val y = cy + sin(angle).toFloat() * r
                val colors = listOf(DiscMint, DiscSky, DiscPink, DiscAmber)
                drawCircle(
                    color = colors[i % colors.size].copy(alpha = if (recording) 0.85f else 0.45f),
                    radius = if (recording) 5.dp.toPx() else 3.5.dp.toPx(),
                    center = Offset(x, y),
                )
            }

            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        Accent.copy(alpha = if (recording) 0.28f else 0.12f),
                        Color.Transparent,
                    ),
                    center = Offset(cx, cy),
                    radius = radius * 0.55f,
                ),
                radius = radius * 0.55f,
                center = Offset(cx, cy),
            )
        }

        Text(
            text = if (recording) "正在倾听…" else "听见这一刻",
            color = White.copy(alpha = 0.55f),
            fontSize = 13.sp,
        )
    }
}

@Composable
private fun RecordButton(
    recording: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.size(92.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(83.dp)
                .border(
                    width = 1.dp,
                    color = if (recording) Accent else White,
                    shape = CircleShape,
                ),
        )
        Box(
            modifier = Modifier
                .size(if (recording) 58.dp else 73.dp)
                .shadow(6.dp, CircleShape)
                .clip(if (recording) RoundedCornerShape(14.dp) else CircleShape)
                .background(if (recording) Accent else White)
                .clickable(
                    indication = null,
                    interactionSource = remember { MutableInteractionSource() },
                    onClick = onClick,
                ),
        )
    }
}

@Preview(
    name = "Home",
    showBackground = true,
    backgroundColor = 0xFF000000,
    widthDp = 393,
    heightDp = 852,
)
@Composable
fun HomeScreenPreview() {
    SoundpolaTheme {
        HomeScreen()
    }
}
