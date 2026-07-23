package com.soundpola.app.data

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.graphics.Color
import com.soundpola.app.ui.theme.Primary300
import com.soundpola.app.ui.theme.Primary500
import com.soundpola.app.ui.theme.Primary600
import com.soundpola.app.ui.theme.Primary700
import java.util.UUID

enum class SoundStatus {
    Drafted,
    Writing,
    WriteFailed,
    ChainPending,
    ChainFailed,
    Collected,
}

data class SoundMemory(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val category: String,
    val description: String = "",
    val durationSec: Int,
    val recordedAtMillis: Long = System.currentTimeMillis(),
    val locationLabel: String = "地点未记录",
    val deviceLabel: String = "Android Phone",
    val status: SoundStatus = SoundStatus.Drafted,
    val visualHue: Float = 0.45f,
    val visualSeed: Int = (0..9999).random(),
    val discId: String? = null,
    val assetId: String? = null,
) {
    val visualColors: List<Color>
        get() = listOf(Primary500, Primary300, Primary600, Primary700)
}

val SoundCategories = listOf(
    "自然", "城市", "人声", "日常", "旅行", "特别时刻", "其他",
)

object SoundRepository {
    val sounds: SnapshotStateList<SoundMemory> = mutableStateListOf(
        SoundMemory(
            title = "雨落窗台",
            category = "自然",
            description = "午后忽然下起小雨。",
            durationSec = 28,
            locationLabel = "杭州 · 西湖",
            status = SoundStatus.Drafted,
            visualSeed = 1201,
        ),
        SoundMemory(
            title = "地铁报站",
            category = "城市",
            description = "",
            durationSec = 12,
            locationLabel = "上海",
            status = SoundStatus.WriteFailed,
            visualSeed = 3340,
        ),
        SoundMemory(
            title = "凌晨的风",
            category = "自然",
            description = "NFC 已写入，等待上链",
            durationSec = 18,
            locationLabel = "大理",
            status = SoundStatus.ChainFailed,
            discId = "SP-2026-0312-C2",
            visualSeed = 4412,
        ),
        SoundMemory(
            title = "散场前的合唱",
            category = "特别时刻",
            description = "没有拍舞台，只留下身边一起唱的声音。",
            durationSec = 46,
            locationLabel = "首尔 · 汉江",
            status = SoundStatus.Collected,
            discId = "SP-2026-0718-A3",
            assetId = "0x8f2a…c91",
            visualSeed = 7788,
        ),
        SoundMemory(
            title = "妈妈说早点回来",
            category = "人声",
            description = "电话里很短的一句。",
            durationSec = 9,
            locationLabel = "地点未记录",
            status = SoundStatus.Collected,
            discId = "SP-2026-0702-B1",
            assetId = "0x11cd…90e",
            visualSeed = 5521,
        ),
    )

    fun drafts(): List<SoundMemory> =
        sounds.filter { it.status != SoundStatus.Collected }

    fun collection(): List<SoundMemory> =
        sounds.filter { it.status == SoundStatus.Collected }

    fun get(id: String): SoundMemory? = sounds.find { it.id == id }

    fun addDraft(memory: SoundMemory) {
        sounds.add(0, memory.copy(status = SoundStatus.Drafted))
    }

    fun update(id: String, transform: (SoundMemory) -> SoundMemory) {
        val index = sounds.indexOfFirst { it.id == id }
        if (index >= 0) sounds[index] = transform(sounds[index])
    }

    fun delete(id: String): Boolean {
        val item = get(id) ?: return false
        if (item.status == SoundStatus.ChainFailed || item.status == SoundStatus.ChainPending) {
            // NFC written but chain failed — deletion blocked per IA
            if (item.discId != null) return false
        }
        return sounds.removeAll { it.id == id }
    }

    fun markCollected(id: String, discId: String, assetId: String) {
        update(id) {
            it.copy(
                status = SoundStatus.Collected,
                discId = discId,
                assetId = assetId,
            )
        }
    }
}

fun formatDuration(sec: Int): String {
    val m = sec / 60
    val s = sec % 60
    return "%d:%02d".format(m, s)
}

fun formatRecordedAt(millis: Long): String {
    val cal = java.util.Calendar.getInstance().apply { timeInMillis = millis }
    return "%04d.%02d.%02d  %02d:%02d".format(
        cal.get(java.util.Calendar.YEAR),
        cal.get(java.util.Calendar.MONTH) + 1,
        cal.get(java.util.Calendar.DAY_OF_MONTH),
        cal.get(java.util.Calendar.HOUR_OF_DAY),
        cal.get(java.util.Calendar.MINUTE),
    )
}
