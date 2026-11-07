package com.tryo.healthassistant

import android.content.Intent
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "health_connect_direct"
    private var pendingResult: MethodChannel.Result? = null
    private val healthPermissionRequestCode = 9001

    // The Health Connect permission contract (connect-client 1.2.0-alpha02).
    // Used directly here instead of registerForActivityResult, because this
    // FlutterActivity extends android.app.Activity (not ComponentActivity),
    // so the `health` plugin's (activity as ComponentActivity) cast fails
    // and its permission launcher is never created — which is why the
    // permission prompt never appeared and the app never showed up in
    // Health Connect's App permissions list.
    private val permissionContract =
        PermissionController.createRequestPermissionResultContract()

    private val wantedPermissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
    )

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

    // Direct Health Connect permission request: build the permission
    // intent from the contract and launch it with the classic
    // startActivityForResult (available on android.app.Activity).
    private fun requestHealthConnectPermissions(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.success(false)
            return
        }
        pendingResult = result
        try {
            val intent = permissionContract.createIntent(this, wantedPermissions)
            startActivityForResult(intent, healthPermissionRequestCode)
        } catch (e: Exception) {
            pendingResult = null
            result.success(false)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != healthPermissionRequestCode) return
        val res = pendingResult
        pendingResult = null
        if (res == null) return
        try {
            val granted = permissionContract.parseResult(resultCode, data)
            res.success(granted.containsAll(wantedPermissions))
        } catch (e: Exception) {
            res.success(false)
        }
    }
}
