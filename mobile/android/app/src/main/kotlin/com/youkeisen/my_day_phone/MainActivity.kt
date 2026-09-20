package com.youkeisen.my_day_phone

import android.content.ComponentName
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
                    // ---- 自启动（v1.8.0）----
                    "openAutoStartSettings" ->
                        result.success(openAutoStartSettings())
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

    // ---------- 自启动（v1.8.0，凯森 2026-09-21 要的） ----------

    /// 为什么非要这一块：国产 ROM（小米/华为/OPPO/vivo/荣耀…）额外加了一层
    /// 「自启动」开关。关着的时候，系统重启或进程被回收之后，App **不会被拉起来**，
    /// 于是开机补提醒（`BootReceiver`）根本没机会跑 —— 表现就是
    /// 「手机重启后，课表提醒再也不响了」。
    ///
    /// 难点：**安卓没有标准的自启动 Intent**，每家 ROM 的管理页包名和类名都不一样，
    /// 也没有任何 API 能查「开关现在是开还是关」。
    /// 所以只能：按厂商挨个试着跳，能跳到专门的管理页就算成功（返回 true），
    /// 全都不存在就退到应用详情页（返回 false），让 Dart 侧提示用户自己找。

    /// 当前机型最可能是哪几家（小写）。
    private fun romHints(): Set<String> {
        val vals = listOf(Build.MANUFACTURER, Build.BRAND, Build.PRODUCT, Build.DEVICE)
            .map { it.lowercase() }
        return vals.toSet()
    }

    /// 跳自启动管理页。返回「是否跳到了专门的自启动页」。
    private fun openAutoStartSettings(): Boolean {
        val hints = romHints()
        // 把命中当前机型的那几项排前面，其余兜底
        val ordered = autoStartCandidates().sortedByDescending { (hint, _) ->
            if (hints.any { it.contains(hint) }) 2
            else if (hint == "generic") 1 else 0
        }
        for ((_, cn) in ordered) {
            if (tryOpen(cn)) return true
        }
        // 全都没有 → 退应用详情页（至少能找到「电池 / 权限」那一栏）
        openAppSettings()
        return false
    }

    /// 所有已知的自启动管理页，第一项是厂商关键词（用来排序）。
    private fun autoStartCandidates(): List<Pair<String, ComponentName>> =
        listOf(
            // vivo（凯森这台 S10 就是这个）：i 管家 / 权限管理。
            // BgStartUpManagerActivity 是真机实测跳到的**专门的自启动管理页**
            // （2026-09-21 验证：topResumedActivity=com.vivo.permissionmanager/
            // .activity.BgStartUpManagerActivity）；只跳到 PurviewTabActivity 的话
            // 停在「权限管理」的列表页，用户还得自己点进「自启动」那一项。
            "vivo" to cn("com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            "vivo" to cn("com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.PurviewTabActivity"),
            "vivo" to cn("com.vivo.abe",
                "com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity"),
            // 小米 / Redmi：安全中心的「自启动管理」
            "xiaomi" to cn("com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            "redmi" to cn("com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            // OPPO / 一加 / realme（ColorOS 各代包名都留着）
            "oppo" to cn("com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            "oplus" to cn("com.oplus.safecenter",
                "com.oplus.safecenter.permission.startup.StartupAppListActivity"),
            "realme" to cn("com.coloros.safecenter",
                "com.coloros.safecenter.startupmanager.StartupAppListActivity"),
            // 华为 EMUI
            "huawei" to cn("com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            "huawei" to cn("com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"),
            // 荣耀 MagicOS
            "honor" to cn("com.hihonor.systemmanager",
                "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            // 三星
            "samsung" to cn("com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity"),
            "samsung" to cn("com.samsung.android.sm",
                "com.samsung.android.sm.ui.battery.BatteryActivity"),
            // 魅族
            "meizu" to cn("com.meizu.safe",
                "com.meizu.safe.security.SHOW_APPSEC"),
            // 联想
            "lenovo" to cn("com.lenovo.security",
                "com.lenovo.security.purchase.SettingsActivity"),
            // 中兴
            "zte" to cn("com.zte.heartyservice",
                "com.zte.heartyservice.autorun.AppAutoRunManagerActivity"),
            // 锤子 / 坚果
            "smartisan" to cn("com.smartisanos.security",
                "com.smartisanos.security.MainActivity"),
            // nexus / pixel 这类原生 ROM 没有自启动页，
            // 走 generic（排序到最后）直接退应用详情页
            "generic" to cn("", ""),
        )

    private fun cn(pkg: String, cls: String): ComponentName = ComponentName(pkg, cls)

    /// 试着打开一个页面。**先 resolve 再 start** —— 直接 start 的话，
    /// 目标不存在会抛 ActivityNotFoundException（虽然 catch 住了，
    /// 但猜错一堆会白白消耗时间），resolveActivity 能提前判掉。
    private fun tryOpen(cn: ComponentName): Boolean {
        if (cn.packageName.isEmpty()) return false
        return try {
            val intent = Intent().apply {
                component = cn
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                // 有些 ROM 的自启动页需要知道是哪个应用
                putExtra("package_name", packageName)
                putExtra("package", packageName)
            }
            if (packageManager.resolveActivity(intent, 0) == null) return false
            startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }
}
