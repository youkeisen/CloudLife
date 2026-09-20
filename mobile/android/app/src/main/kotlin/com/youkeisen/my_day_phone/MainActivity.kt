package com.youkeisen.my_day_phone

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// 主界面：除了跑 Flutter，还挂一个 `cloudlife/system` 通道，
/// 供设置页查询/跳转电池优化白名单（v1.6.0，需求文档第 8 条），
/// 以及查询/申请「所有文件访问」权限（v1.7.3 修备份位置写不进去）。
///
/// 为什么需要这个：凯森选了「不加常驻通知」，那提醒能不能准时响就取决于
/// 系统有没有把本应用放进电池优化白名单。放进去了系统就不会在省电时
/// 把闹钟压到很晚；放不进去也不至于完全不响，只是会晚一点。
class MainActivity : FlutterActivity() {
    private val channelName = "cloudlife/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBatteryOptimizationDisabled" ->
                        result.success(isBatteryOptimizationDisabled())
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    // ---- 所有文件访问（v1.7.3）----
                    "hasManageExternalStorage" ->
                        result.success(hasManageExternalStorage())
                    "requestManageExternalStorage" -> {
                        requestManageExternalStorage()
                        result.success(null)
                    }
                    // ---- 精确闹钟（v1.7.4）----
                    "openExactAlarmSettings" -> {
                        openExactAlarmSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isBatteryOptimizationDisabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (_: Throwable) {
            false
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (_: Throwable) {
            // 少数 ROM 不认这个 action，退回应用详情页
            openAppSettings()
        }
    }

    private fun openAppSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (_: Throwable) {
            // 打不开就算了，设置页里已经写了手动路径
        }
    }

    // ---------- 所有文件访问（v1.7.3） ----------

    /// 是否已拿到「所有文件访问」权限。
    /// Android 11+（R）才要求这个权限；11 以下旧机型直接按「有」处理，
    /// 免得在能正常写盘的老机器上误报。
    private fun hasManageExternalStorage(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return true
        return try {
            Environment.isExternalStorageManager()
        } catch (_: Throwable) {
            false
        }
    }

    /// 跳到系统的「所有文件访问」授权页，让用户手动打开。
    /// 注意：这是敏感权限，系统**只给跳转、不给一键授权**，用户必须自己点。
    /// 少数 ROM（一加/OPPO 等）这个 action 打不开，退回应用详情页兜底。
    private fun requestManageExternalStorage() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (_: Throwable) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                startActivity(intent)
            } catch (_: Throwable) {
                openAppSettings()
            }
        }
    }

    // ---------- 精确闹钟（v1.7.4） ----------

    /// 跳到「闹钟和提醒」授权页，让用户允许本应用使用精确闹钟。
    ///
    /// 为什么需要：提醒用的是非精确闹钟，安卓会把它们**攒起来延后触发**，
    /// 省电模式下晚十几分钟很常见（用户反馈「到点没提醒」的原因之一）。
    /// 这个 action 要 Android 12（S）才有，旧机型直接退应用详情页。
    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            openAppSettings()
            return
        }
        try {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        } catch (_: Throwable) {
            openAppSettings()
        }
    }
}
