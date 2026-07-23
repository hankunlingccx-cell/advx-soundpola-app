package com.soundpola.app.ui.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.soundpola.app.ui.collection.CollectionScreen
import com.soundpola.app.ui.collection.MemoryScreen
import com.soundpola.app.ui.components.BottomNavBar
import com.soundpola.app.ui.drafts.DraftDetailScreen
import com.soundpola.app.ui.drafts.DraftsScreen
import com.soundpola.app.ui.press.PressConfirmScreen
import com.soundpola.app.ui.press.PressDetectScreen
import com.soundpola.app.ui.press.PressDoneScreen
import com.soundpola.app.ui.press.PressMethodScreen
import com.soundpola.app.ui.press.PressProgressScreen
import com.soundpola.app.ui.record.PermissionScreen
import com.soundpola.app.ui.record.RecordHomeScreen
import com.soundpola.app.ui.record.RecordingScreen
import com.soundpola.app.ui.record.ResultScreen
import com.soundpola.app.ui.theme.CanvasBg

@Composable
fun SoundpolaApp() {
    val navController = rememberNavController()
    var consented by rememberSaveable { mutableStateOf(false) }

    NavHost(
        navController = navController,
        startDestination = if (consented) Routes.main() else Routes.Permission,
        modifier = Modifier
            .fillMaxSize()
            .background(CanvasBg)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        composable(Routes.Permission) {
            PermissionScreen(
                onContinue = {
                    consented = true
                    navController.navigate(Routes.main()) {
                        popUpTo(Routes.Permission) { inclusive = true }
                    }
                },
            )
        }

        composable(
            route = Routes.Main,
            arguments = listOf(navArgument("tab") {
                type = NavType.IntType
                defaultValue = 0
            }),
        ) { entry ->
            val startTab = entry.arguments?.getInt("tab") ?: 0
            MainTabs(
                startTab = startTab,
                onStartRecord = { navController.navigate(Routes.Recording) },
                onOpenDraft = { navController.navigate(Routes.draftDetail(it)) },
                onPress = { navController.navigate(Routes.pressMethod(it)) },
                onOpenMemory = { navController.navigate(Routes.memory(it)) },
            )
        }

        composable(Routes.Recording) {
            RecordingScreen(
                onCancel = { navController.popBackStack() },
                onComplete = { duration ->
                    navController.navigate(Routes.result(duration)) {
                        popUpTo(Routes.Recording) { inclusive = true }
                    }
                },
            )
        }

        composable(
            route = Routes.Result,
            arguments = listOf(navArgument("duration") { type = NavType.IntType }),
        ) { entry ->
            val duration = entry.arguments?.getInt("duration") ?: 1
            ResultScreen(
                durationSec = duration,
                onSaved = {
                    navController.navigate(Routes.main(tab = 1)) {
                        popUpTo(0) { inclusive = false }
                        launchSingleTop = true
                    }
                },
                onReRecord = {
                    navController.navigate(Routes.Recording) {
                        popUpTo(Routes.Result) { inclusive = true }
                    }
                },
            )
        }

        composable(
            route = Routes.DraftDetail,
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            DraftDetailScreen(
                id = id,
                onBack = { navController.popBackStack() },
                onPress = { navController.navigate(Routes.pressMethod(id)) },
                onDeleted = { navController.popBackStack() },
            )
        }

        composable(
            route = Routes.PressMethod,
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            PressMethodScreen(
                id = id,
                onBack = { navController.popBackStack() },
                onNfc = { navController.navigate(Routes.pressDetect(id)) },
            )
        }

        composable(
            route = Routes.PressDetect,
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            PressDetectScreen(
                id = id,
                onBack = { navController.popBackStack() },
                onDetected = { navController.navigate(Routes.pressConfirm(id)) },
            )
        }

        composable(
            route = Routes.PressConfirm,
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            PressConfirmScreen(
                id = id,
                onBack = { navController.popBackStack() },
                onConfirm = { navController.navigate(Routes.pressProgress(id)) },
            )
        }

        composable(
            route = Routes.PressProgress,
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            PressProgressScreen(
                id = id,
                onDone = {
                    navController.navigate(Routes.pressDone(id)) {
                        popUpTo(Routes.Main) { inclusive = false }
                    }
                },
            )
        }

        composable(
            route = Routes.PressDone,
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            PressDoneScreen(
                id = id,
                onCollection = {
                    navController.navigate(Routes.main(tab = 2)) {
                        popUpTo(0) { inclusive = false }
                        launchSingleTop = true
                    }
                },
                onMemory = { navController.navigate(Routes.memory(id)) },
            )
        }

        composable(
            route = Routes.Memory,
            arguments = listOf(navArgument("id") { type = NavType.StringType }),
        ) { entry ->
            val id = entry.arguments?.getString("id").orEmpty()
            MemoryScreen(
                id = id,
                onBack = { navController.popBackStack() },
            )
        }
    }
}

@Composable
private fun MainTabs(
    startTab: Int,
    onStartRecord: () -> Unit,
    onOpenDraft: (String) -> Unit,
    onPress: (String) -> Unit,
    onOpenMemory: (String) -> Unit,
) {
    var tab by rememberSaveable { mutableIntStateOf(startTab) }
    LaunchedEffect(startTab) { tab = startTab }

    Column(modifier = Modifier.fillMaxSize()) {
        Box(modifier = Modifier.weight(1f)) {
            when (tab) {
                0 -> RecordHomeScreen(onStartRecord = onStartRecord)
                1 -> DraftsScreen(
                    onOpenDetail = onOpenDraft,
                    onPress = onPress,
                    onStartRecord = {
                        tab = 0
                        onStartRecord()
                    },
                )
                else -> CollectionScreen(onOpenMemory = onOpenMemory)
            }
        }
        BottomNavBar(selected = tab, onSelect = { tab = it })
    }
}
