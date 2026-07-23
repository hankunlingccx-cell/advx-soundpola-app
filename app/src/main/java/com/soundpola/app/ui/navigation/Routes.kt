package com.soundpola.app.ui.navigation

object Routes {
    const val Permission = "permission"
    const val Main = "main?tab={tab}"
    const val Recording = "recording"
    const val Result = "result/{duration}"
    const val DraftDetail = "draft/{id}"
    const val PressMethod = "press/method/{id}"
    const val PressDetect = "press/detect/{id}"
    const val PressConfirm = "press/confirm/{id}"
    const val PressProgress = "press/progress/{id}"
    const val PressDone = "press/done/{id}"
    const val Memory = "memory/{id}"

    fun main(tab: Int = 0) = "main?tab=$tab"
    fun result(duration: Int) = "result/$duration"
    fun draftDetail(id: String) = "draft/$id"
    fun pressMethod(id: String) = "press/method/$id"
    fun pressDetect(id: String) = "press/detect/$id"
    fun pressConfirm(id: String) = "press/confirm/$id"
    fun pressProgress(id: String) = "press/progress/$id"
    fun pressDone(id: String) = "press/done/$id"
    fun memory(id: String) = "memory/$id"
}
