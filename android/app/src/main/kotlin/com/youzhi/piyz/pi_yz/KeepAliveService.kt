package com.youzhi.piyz.pi_yz

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * 后台保活：让「手机退到后台也不断线」真的成立。
 *
 * 为什么必须有它（task-10/11 留下的已知不足）：
 *   Android 8 以后，App 一退到后台，系统就会冻结它的定时器、限流它的网络，
 *   再过一会儿可能整个进程被回收。原来的实现只在**回到前台时重连**
 *   （`resumeSync`），这意味着「用户睡着了」的那几个小时里：
 *     · 服务端推送的卡住/跑完事件根本收不到；
 *     · 卡住提醒的 5 秒定时器不跳；
 *     · 醒来一看是断的，还得手动点一下。
 *   这恰好是无人值守最需要的那段时间，所以必须起一个**前台服务**：
 *   系统把「带常驻通知的服务」当作用户知情且正在使用的进程，不冻结、不轻易回收。
 *
 * 里面做了三件事：
 *   1. `startForeground` + 常驻低优先级通知 —— 这是保活的前提（也是规矩：
 *      保活必须让用户看得见，偷偷保活是流氓行为）；
 *   2. 持一个 `PARTIAL_WAKE_LOCK` —— 屏幕关了 CPU 也不睡，定时器照跳；
 *   3. 持一个 `WifiLock`（HIGH_PERF）—— 息屏后 Wi-Fi 射频不降频，SSE 长连接不掉。
 *
 * 代价（界面上要如实写）：常驻通知栏会多一条；耗电比不保活高。
 * 所以它做成**可关的开关**，默认在连接成功后自动开，用户随时能关。
 */
class KeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "pi_keepalive"
        const val NOTIF_ID = 9901
        const val ACTION_START = "com.youzhi.piyz.pi_yz.KEEPALIVE_START"
        const val ACTION_STOP = "com.youzhi.piyz.pi_yz.KEEPALIVE_STOP"

        /** 供 Dart 查询：服务是不是在跑（进程内静态量，够用且不用跨进程问） */
        @Volatile
        var running: Boolean = false
            private set
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIF_ID, buildNotification())
        acquireLocks()
        running = true

        // START_STICKY：万一还是被系统杀了，让它自己重建 —— 保活的最后一道保险
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        releaseLocks()
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "后台保持连接",
            // IMPORTANCE_MIN：常驻但完全不打扰（不响不震不弹，也不上状态栏图标）
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "保持与电脑端 pi 的连接，退到后台也收得到进度与提醒"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0),
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("pi-mobile 正在保持连接")
            .setContentText("退到后台也能收到进度与提醒 · 在设置里可关闭")
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentIntent(pending)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun acquireLocks() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (wakeLock == null) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "pi-mobile:keepalive")
                wakeLock?.setReferenceCounted(false)
            }
            if (wakeLock?.isHeld != true) wakeLock?.acquire()
        } catch (_: Exception) {
            // 拿不到就算了：前台服务本身已经能挡掉大部分回收
        }

        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (wifiLock == null) {
                wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "pi-mobile:wifi")
                wifiLock?.setReferenceCounted(false)
            }
            if (wifiLock?.isHeld != true) wifiLock?.acquire()
        } catch (_: Exception) {
            // 同上
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        wifiLock = null
    }
}
