package com.youkeisen.my_day_phone

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// 开机 / 应用被更新后，把定时提醒重新排一遍（v1.6.0，需求文档第 8 条：
/// 「让软件可以一直在后台运行，使提醒功能可以正常使用」）。
///
/// 说明为什么不是「常驻前台服务」：凯森选了不加常驻通知的方案，所以走的是
/// 「系统闹钟 + 开机重排」这条路——通知排进系统 AlarmManager 之后，App 就算
/// 被系统清掉，到点照样响；重启后由这个接收器把未来一周的提醒补回去。
///
/// 这里**不写业务逻辑**，只是把 Flutter 引擎拉起来跑一次 Dart 侧的
/// 重排（见 `lib/boot_reschedule.dart` + `BootRescheduleWorker`）。
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        // 交给无界面引擎处理；失败也不能崩（开机阶段崩了会被系统记一笔）。
        try {
            BootRescheduleWorker.schedule(context)
        } catch (_: Throwable) {
            // 忽略：提醒晚排一次不影响别的功能
        }
    }
}
