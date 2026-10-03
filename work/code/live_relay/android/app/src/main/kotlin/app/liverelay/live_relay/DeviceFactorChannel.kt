package app.liverelay.live_relay

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Independent per-operation Keystore branch. No VMK or legacy storage access. */
class DeviceFactorChannel(
    private val activity: FlutterFragmentActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "app.liverelay/device-factor-v1")
    private val handler = Handler(Looper.getMainLooper())
    private val keyStore by lazy {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    }
    private var operation: Operation? = null
    private var prompt: BiometricPrompt? = null
    private val timeout = Runnable { cancelOperation() }

    private data class Operation(
        val result: MethodChannel.Result,
        val alias: String,
        val creating: Boolean,
        val input: ByteArray,
    )

    init { channel.setMethodCallHandler(this) }

    private fun alias(reference: String): String {
        require(Regex("^[0-9a-f]{32}$").matches(reference))
        return "liverelay.factor.v2.$reference"
    }

    private fun bytes(call: MethodCall, name: String, length: Int): ByteArray {
        val value = call.argument<ByteArray>(name) ?: throw IllegalArgumentException()
        require(value.size == length)
        return value
    }

    private fun available(): Boolean = try {
        keyStore // A missing/broken provider disables the feature without blocking password startup.
        BiometricManager.from(activity).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS
    } catch (_: Exception) { false }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "capability") {
            result.success(if (available()) "available" else "unavailable")
            return
        }
        if (call.method == "cancel") {
            cancelOperation()
            result.success(null)
            return
        }
        if (call.method !in setOf("protect", "unprotect", "delete")) {
            result.notImplemented()
            return
        }
        if (operation != null) {
            call.argument<ByteArray>("share")?.fill(0)
            result.error("busy", "正在进行设备授权", null)
            return
        }
        var createdAlias: String? = null
        var inputToClear: ByteArray? = null
        try {
            val reference = call.argument<String>("reference") ?: throw IllegalArgumentException()
            val keyAlias = alias(reference)
            if (call.method == "protect") inputToClear = call.argument<ByteArray>("share")
            if (call.method == "delete") {
                keyStore.deleteEntry(keyAlias)
                result.success(null)
                return
            }
            if (!available()) {
                inputToClear?.fill(0)
                result.error("unavailable", "强生物识别不可用", null)
                return
            }
            val aad = call.argument<ByteArray>("aad") ?: throw IllegalArgumentException()
            require(aad.isNotEmpty() && aad.size <= 1024)
            val creating = call.method == "protect"
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val input: ByteArray
            if (creating) {
                input = bytes(call, "share", 32)
                inputToClear = input
                // A reference is single-use; never overwrite a live branch key.
                require(!keyStore.containsAlias(keyAlias))
                val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                val builder = KeyGenParameterSpec.Builder(
                    keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                ).setKeySize(256)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .setUserAuthenticationRequired(true)
                    .setInvalidatedByBiometricEnrollment(true)
                if (Build.VERSION.SDK_INT >= 30) {
                    builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                } else {
                    @Suppress("DEPRECATION")
                    builder.setUserAuthenticationValidityDurationSeconds(-1)
                }
                generator.init(builder.build())
                val key = generator.generateKey()
                createdAlias = keyAlias
                cipher.init(Cipher.ENCRYPT_MODE, key)
            } else {
                val key = keyStore.getKey(keyAlias, null) as? SecretKey
                if (key == null) {
                    result.error("missing", "本机设备密钥不存在", null)
                    return
                }
                val nonce = bytes(call, "nonce", 12)
                input = bytes(call, "cipherText", 32) + bytes(call, "mac", 16)
                inputToClear = input
                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
            }
            cipher.updateAAD(aad)
            val active = Operation(result, keyAlias, creating, input)
            operation = active
            val biometricPrompt = BiometricPrompt(
                activity, ContextCompat.getMainExecutor(activity),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                        if (operation !== active) return
                        var clear: ByteArray? = null
                        try {
                            val authorized = auth.cryptoObject?.cipher ?: throw IllegalStateException()
                            val output = authorized.doFinal(active.input)
                            if (active.creating) {
                                require(authorized.iv.size == 12 && output.size == 48)
                                succeed(active, mapOf(
                                    "nonce" to authorized.iv,
                                    "cipherText" to output.copyOfRange(0, 32),
                                    "mac" to output.copyOfRange(32, 48),
                                ))
                            } else {
                                clear = output
                                require(output.size == 32)
                                // MethodChannel encodes synchronously before controlled bytes are wiped.
                                succeed(active, output)
                            }
                        } catch (error: Exception) {
                            fail(active, errorCode(error))
                        } finally { clear?.fill(0) }
                    }

                    override fun onAuthenticationError(code: Int, message: CharSequence) {
                        if (operation !== active) return
                        val reason = when (code) {
                            BiometricPrompt.ERROR_CANCELED,
                            BiometricPrompt.ERROR_USER_CANCELED,
                            BiometricPrompt.ERROR_NEGATIVE_BUTTON -> "cancelled"
                            BiometricPrompt.ERROR_NO_BIOMETRICS,
                            BiometricPrompt.ERROR_HW_NOT_PRESENT,
                            BiometricPrompt.ERROR_HW_UNAVAILABLE -> "unavailable"
                            else -> "failed"
                        }
                        fail(active, reason)
                    }
                },
            )
            prompt = biometricPrompt
            handler.postDelayed(timeout, 60_000)
            biometricPrompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle(if (creating) "启用留灯指纹解锁" else "用指纹解锁留灯")
                    .setSubtitle("授权本机设备密钥")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                    .setNegativeButtonText("取消")
                    .build(),
                BiometricPrompt.CryptoObject(cipher),
            )
        } catch (error: Exception) {
            val active = operation
            if (active != null) fail(active, errorCode(error))
            else {
                createdAlias?.let { try { keyStore.deleteEntry(it) } catch (_: Exception) {} }
                inputToClear?.fill(0)
                result.error(errorCode(error), "设备保护操作未完成", null)
            }
        }
    }

    private fun errorCode(error: Exception): String = when (error) {
        is KeyPermanentlyInvalidatedException -> "invalidated"
        is AEADBadTagException, is IllegalArgumentException -> "rejected"
        else -> "failed"
    }

    private fun finish(active: Operation) {
        if (operation !== active) return
        operation = null
        handler.removeCallbacks(timeout)
        prompt = null
        active.input.fill(0)
    }

    private fun succeed(active: Operation, value: Any) {
        finish(active)
        active.result.success(value)
    }

    private fun fail(active: Operation, reason: String) {
        finish(active)
        if (active.creating) {
            try { keyStore.deleteEntry(active.alias) } catch (_: Exception) {}
        }
        active.result.error(reason, "设备保护操作未完成", null)
    }

    fun cancelOperation() {
        val active = operation ?: return
        val currentPrompt = prompt
        fail(active, "cancelled")
        currentPrompt?.cancelAuthentication()
    }

    fun close() {
        cancelOperation()
        channel.setMethodCallHandler(null)
    }
}
