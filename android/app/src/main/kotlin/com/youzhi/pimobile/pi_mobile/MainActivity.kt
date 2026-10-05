package com.youzhi.pimobile.pi_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 原生能力桥。三件事：
 *   share / saveImage  —— 分享面板、存相册（task-9）
 *   notify / cancel    —— 状态通知 + 通知栏快速回复（task-11）
 *
 * 全部用**框架自带** API（android.app.*），不引 androidx / 第三方通知库：
 * 依赖越少，越不容易在 Flutter 升级后炸。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "pi_mobile/native"
    private val channelId = "pi_agent_status"
    private val replyAction = "com.youzhi.pimobile.pi_mobile.QUICK_REPLY"
    private val keyReplyText = "pi_reply_text"
    private var channel: MethodChannel? = null

    /// 通知点击带过来的会话 id（App 起来后自己取走）
    private var launchSessionId: String? = null

    private val replyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val results = RemoteInput.getResultsFromIntent(intent) ?: return
            val text = results.getCharSequence(keyReplyText)?.toString() ?: return
            if (text.isBlank()) return
            val sessionId = intent.getStringExtra("sessionId") ?: ""
            // 回复内容交给 Dart 侧（那里才知道往哪个会话、用什么方式发）
            channel?.invokeMethod(
                "onQuickReply",
                mapOf("text" to text, "sessionId" to sessionId)
            )
            // 回复过的通知就地撤掉：内容已经进会话了，留着只会让人以为没发出去
            val id = intent.getIntExtra("notificationId", 0)
            if (id != 0) {
                (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(id)
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createChannel()
        readSessionFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        readSessionFromIntent(intent)
        // 通知点击时 App 可能已经在后台：把会话 id 直接推给 Dart，不必等它轮询
        launchSessionId?.let { id ->
            channel?.invokeMethod("onOpenSession", mapOf("sessionId" to id))
        }
    }

    private fun readSessionFromIntent(intent: Intent?) {
        val id = intent?.getStringExtra("sessionId")
        if (!id.isNullOrEmpty()) launchSessionId = id
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(channelId) != null) return
        val channel = NotificationChannel(
            channelId,
            "会话状态",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "pi agent 跑完、需要你确认或出错时提醒"
        }
        manager.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "share" -> {
                    val text = call.argument<String>("text") ?: ""
                    val subject = call.argument<String>("subject") ?: "pi agent 会话片段"
                    if (text.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                    }
                    startActivity(Intent.createChooser(intent, "分享到"))
                    result.success(true)
                }

                "saveImage" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name")
                        ?: "pi-" + System.currentTimeMillis() + ".png"
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("no_bytes", "没有收到图片数据", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(saveToGallery(bytes, name))
                    } catch (error: Exception) {
                        result.error("save_failed", error.message ?: "保存失败", null)
                    }
                }

                // ---- 后台保活（转给 KeepAliveService）----
                "keepAliveStart" -> {
                    try {
                        val intent = Intent(this, KeepAliveService::class.java)
                            .setAction(KeepAliveService.ACTION_START)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("keepalive_failed", error.message ?: "起不了保活服务", null)
                    }
                }

                "keepAliveStop" -> {
                    try {
                        stopService(Intent(this, KeepAliveService::class.java))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("keepalive_failed", error.message ?: "停不了保活服务", null)
                    }
                }

                "keepAliveStatus" -> result.success(KeepAliveService.running)

                "notify" -> {
                    try {
                        val id = (call.argument<Int>("id") ?: 1)
                        val title = call.argument<String>("title") ?: "pi agent"
                        val body = call.argument<String>("body") ?: ""
                        val sessionId = call.argument<String>("sessionId") ?: ""
                        val replyable = call.argument<Boolean>("replyable") ?: false
                        notifyStatus(id, title, body, sessionId, replyable)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("notify_failed", error.message ?: "通知发不出去", null)
                    }
                }

                "cancel" -> {
                    val id = call.argument<Int>("id")
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (id == null) manager.cancelAll() else manager.cancel(id)
                    result.success(true)
                }

                "permission" -> result.success(hasNotificationPermission())

                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        !hasNotificationPermission()
                    ) {
                        requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 9001)
                    }
                    result.success(true)
                }

                "consumeLaunchSession" -> {
                    // 取走即清：不然每次回前台都会再跳一次同一个会话
                    val id = launchSessionId
                    launchSessionId = null
                    result.success(id)
                }

                else -> result.notImplemented()
            }
        }

        // 通知栏快速回复的接收器：只在 App 进程活着时有意义（回复本来也要靠 App 发出去）
        val filter = IntentFilter(replyAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(replyReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(replyReceiver, filter)
        }
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    private fun notifyStatus(
        id: Int,
        title: String,
        body: String,
        sessionId: String,
        replyable: Boolean,
    ) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasNotificationPermission()) {
            throw IllegalStateException("没有通知权限（POST_NOTIFICATIONS）")
        }

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("sessionId", sessionId)
        }
        val contentIntent = PendingIntent.getActivity(
            this, id, tapIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = Notification.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(contentIntent)

        if (replyable) {
            val replyIntent = Intent(replyAction).apply {
                setPackage(packageName) // 只发给本应用：避免被别的应用伪造回复
                putExtra("sessionId", sessionId)
                putExtra("notificationId", id)
            }
            val replyPi = PendingIntent.getBroadcast(
                this, id + 5000, replyIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            val remoteInput = RemoteInput.Builder(keyReplyText)
                .setLabel("回一句（会作为插话发进去）")
                .build()
            val action = Notification.Action.Builder(
                android.R.drawable.ic_menu_send, "快速回复", replyPi
            ).addRemoteInput(remoteInput).build()
            builder.addAction(action)
        }

        manager.notify(id, builder.build())
    }

    private fun mimeOf(name: String): String = when {
        name.endsWith(".jpg", true) || name.endsWith(".jpeg", true) -> "image/jpeg"
        name.endsWith(".webp", true) -> "image/webp"
        else -> "image/png"
    }

    private fun saveToGallery(bytes: ByteArray, name: String): String {
        val resolver = contentResolver
        val mime = mimeOf(name)
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/pi-mobile"
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }
        val uri: Uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("系统没有给出可写入的位置")
        resolver.openOutputStream(uri)?.use { it.write(bytes) }
            ?: throw IllegalStateException("打不开输出流")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
        }
        return uri.toString()
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(replyReceiver)
        } catch (_: Exception) {
            // 没注册成功过就忽略
        }
        super.onDestroy()
    }
}
