package com.tryo.healthassistant

import android.content.Intent
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val channelName = "health_connect_direct"
    private var pendingResult: MethodChannel.Result? = null

    // Launcher for the Health Connect permission screen. Registered here
    // (before onStart) so it is always ready when Dart asks for it.
    private val permissionLauncher: ActivityResultLauncher<Intent> =
        registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) {
            // The permission screen closed — check what was actually granted.
            lifecycleScope.launch {
                try {
                    val client = HealthConnectClient.getOrCreate(this@MainActivity)
                    val granted = client.permissionController.getGrantedPermissions()
                    val wanted = setOf(
                        HealthPermission.getReadPermission(StepsRecord::class),
                        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
                        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
                    )
                    pendingResult?.success(granted.containsAll(wanted))
                } catch (e: Exception) {
                    pendingResult?.success(false)
                }
                pendingResult = null
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            if (call.method == "requestPermissions") {
                requestHealthConnectPermissions(result)
            } else {
                result.notImplemented()
            }
        }
    }

    // Direct Health Connect permission request using the official API.
    // This bypasses the `health` plugin's ActivityResultLauncher, which
    // does not show the prompt on some devices (the app then never
    // appears in Health Connect's App permissions list).
    private fun requestHealthConnectPermissions(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.success(false)
            return
        }
        pendingResult = result
        lifecycleScope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(this@MainActivity)
                val permissions = setOf(
                    HealthPermission.getReadPermission(StepsRecord::class),
                    HealthPermission.getReadPermission(ExerciseSessionRecord::class),
                    HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
                )
                val intent = client.permissionController
                    .createRequestPermissionIntent(permissions)
                permissionLauncher.launch(intent)
            } catch (e: Exception) {
                pendingResult = null
                result.success(false)
            }
        }
    }
}
