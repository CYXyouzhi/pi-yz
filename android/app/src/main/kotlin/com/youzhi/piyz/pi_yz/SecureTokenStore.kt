package com.youzhi.piyz.pi_yz

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * token 的安全存储：用 Android Keystore 里的 AES 密钥加密后再落盘。
 *
 * ## 为什么要绕一圈加密，而不是「直接把 token 交给 Keystore」
 *
 * Keystore 只负责**保管密钥**，它自己不存业务数据。正确用法就是这个链条：
 *
 * ```
 * Keystore（密钥住这儿，不可导出） → 拿它加密 token → 密文随便存
 * ```
 *
 * 攻击者即使拿到密文文件，没有 Keystore 里那把密钥也解不开；而密钥受系统保护，
 * 有些设备上还有硬件背书（TEE / StrongBox），连 root 都难以导出。
 *
 * ## 四处必须做对的地方（每一处写错都会静默降级成「假安全」）
 *
 * 1. **GCM 而不是 CBC**：CBC 不校验完整性，密文被改一位照样能解出垃圾明文；
 *    GCM 自带认证标签，改过就解不开。
 * 2. **IV 每次随机、且跟密文一起存**：IV 不是秘密，但绝不能重复。
 * 3. **不开 setUserAuthenticationRequired**：开了会要求指纹/锁屏，用户没开锁屏
 *    就直接用不了 —— 那是可用性事故，不是安全收益。
 * 4. **解密失败一律当「读不到」**：换机、清数据、系统重置 Keystore、App 被
 *    备份还原后恢复 —— 这些情况下密钥已经对不上了。返回 null 让上层请用户
 *    重新输入 token，比抛异常崩掉好。
 */
object SecureTokenStore {
    private const val KEY_ALIAS = "pi_yz_token_key_v1"

    /** 单独一个 prefs 文件：Flutter 侧看到的是 `FlutterSharedPreferences`，
     *  这里刻意分开，密文不出现在 Dart 能直接读的那份里。 */
    private const val PREF_NAME = "pi_yz_secure_tokens"

    private const val TRANSFORM = "AES/GCM/NoPadding"
    private const val TAG_BITS = 128
    private const val IV_MARKER = 1 // blob 第一个字节存 IV 长度

    /** Keystore 的 AES/GCM 要 API 23+；低版本返回 false，让上层回落 */
    fun available(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M

    fun put(context: Context, id: String, token: String): Boolean {
        if (!available() || id.isEmpty()) return false
        return try {
            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val iv = cipher.iv
            val encrypted = cipher.doFinal(token.toByteArray(Charsets.UTF_8))

            // blob = [ivLen(1 字节)][iv][密文+认证标签]
            val blob = ByteBuffer.allocate(IV_MARKER + iv.size + encrypted.size)
                .put(iv.size.toByte())
                .put(iv)
                .put(encrypted)
                .array()

            // 用 commit() 而不是 apply()：调用方（迁移逻辑）要根据**真实成败**
            // 决定能不能把明文抹掉，apply() 是异步的、骗不了这个判断。
            // 数据只有几十字节，代价可以忽略。
            prefs(context).edit()
                .putString(keyFor(id), Base64.encodeToString(blob, Base64.NO_WRAP))
                .commit()
        } catch (error: Exception) {
            // 密钥被系统重置、设备不支持……都走这里。返回 false 让上层回落，
            // 而不是「假装写成功了」——后者会让明文被抹掉，token 就真丢了。
            false
        }
    }

    fun get(context: Context, id: String): String? {
        if (!available() || id.isEmpty()) return null
        return try {
            val raw = prefs(context).getString(keyFor(id), null) ?: return null
            val blob = Base64.decode(raw, Base64.NO_WRAP)
            if (blob.size <= IV_MARKER) return null

            val ivLength = blob[0].toInt()
            if (ivLength <= 0 || IV_MARKER + ivLength >= blob.size) return null
            val iv = blob.copyOfRange(IV_MARKER, IV_MARKER + ivLength)
            val encrypted = blob.copyOfRange(IV_MARKER + ivLength, blob.size)

            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(TAG_BITS, iv))
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (error: Exception) {
            // 解不开（换机 / 密钥重置 / 密文损坏）→ 当成没有，上层会让用户重新输入
            null
        }
    }

    fun remove(context: Context, id: String): Boolean {
        if (id.isEmpty()) return false
        return prefs(context).edit().remove(keyFor(id)).commit()
    }

    private fun keyFor(id: String) = "t_$id"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

    /**
     * 拿到密钥；没有就生成一把。
     *
     * 密钥本身**不可导出**（Keystore 保证）：我们只拿到一个句柄，
     * 加解密都得通过它来做。
     */
    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}
