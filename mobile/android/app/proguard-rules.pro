# MyDay 的 R8 / ProGuard 保留规则
#
# ── 为什么会有这个文件 ──
# 2026-09-20 凯森反馈「到点不弹通知并且软件闪退」，连上真机抓 crash buffer 才拿到真凶：
#
#   java.lang.RuntimeException: Unable to start receiver
#       com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver:
#       java.lang.RuntimeException: Missing type parameter.
#   at FlutterLocalNotificationsPlugin.loadScheduledNotifications(...)
#
# 插件源码（flutter_local_notifications 17.2.4）第 508 行：
#   Type type = new TypeToken<ArrayList<NotificationDetails>>() {}.getType();
#   scheduledNotifications = gson.fromJson(json, type);
#
# Gson 靠**匿名 TypeToken 子类的泛型签名**（class 文件里的 Signature 属性）
# 反射拿到 ArrayList<NotificationDetails> 这个具体类型。
# R8 默认会把 Signature 属性擦掉、并把 NotificationDetails 重命名，
# 于是 Gson 读不到类型参数 → 抛 "Missing type parameter"。
#
# 后果：闹钟到点 → receiver 起来 → 读已存通知数据 → 崩 → 进程没了。
# 表现就是「通知永远不弹 + App 闪退」，而且**设置页查「已排提醒」也一起崩**
# （pendingNotificationRequests 走的是同一个 loadScheduledNotifications）。
#
# 修法就是下面这些 keep 规则。**不要删。**

# ── 1. 泛型签名（最关键的一条）────────────────────────────
# Gson 的 TypeToken 全靠它。没有这条，上面的崩溃会原样复现。
-keepattributes Signature

# ── 2. 注解 ─────────────────────────────────────────────
# Gson 的 @SerializedName 等注解被擦掉会导致字段对不上（静默丢数据，更难查）
-keepattributes *Annotation*

# ── 3. Gson 自身 ────────────────────────────────────────
-keep class com.google.gson.** { *; }
-keep class com.google.gson.stream.** { *; }
-dontwarn com.google.gson.**

# TypeToken 的匿名子类（Gson 反射拿类型的入口）
-keep class * extends com.google.gson.reflect.TypeToken { *; }
# 自定义 TypeAdapterFactory（插件的 RuntimeTypeAdapterFactory 走这条）
-keep class * implements com.google.gson.TypeAdapterFactory { *; }
-keep class * implements com.google.gson.JsonSerializer { *; }
-keep class * implements com.google.gson.JsonDeserializer { *; }

# ── 4. flutter_local_notifications 的模型类 ──────────────
# NotificationDetails / StyleInformation 及其子类都是 Gson 的反序列化目标，
# 一旦被重命名或改字段名，JSON 就对不上了。
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.** { *; }

# 枚举的 values()/valueOf()（ScheduleMode 等靠 Gson 反序列化）
-keepclassmembers enum com.dexterous.flutterlocalnotifications.** {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── 5. 其它：通知渠道 / PendingIntent 相关 ────────────────
# 通过字符串或反射引用的资源、组件，一律保住，免得再踩「被优化掉」的坑
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver { *; }
