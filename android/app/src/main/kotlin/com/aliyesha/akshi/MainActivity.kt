package com.aliyesha.akshi

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.DnsResolver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // One AndroidX-controlled system splash is used on every supported API.
        // Rich branding is the first Flutter frame; do not add a native overlay.
        installSplashScreen()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aliyesha.akshi/dns",
        ).setMethodCallHandler { call, result ->
            if (call.method != "query") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val name = call.argument<String>("name")
            val type = call.argument<Int>("type")
            if (name.isNullOrBlank() || type == null) {
                result.error("invalid_arguments", "DNS name and type are required", null)
                return@setMethodCallHandler
            }
            queryDns(name, type, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aliyesha.akshi/external_links",
        ).setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val value = call.argument<String>("url")
            val uri = value?.let(Uri::parse)
            if (uri == null || uri.scheme != "https" || uri.host.isNullOrBlank()) {
                result.error("invalid_url", "A valid HTTPS URL is required", null)
                return@setMethodCallHandler
            }
            try {
                startActivity(
                    Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE),
                )
                result.success(true)
            } catch (_: ActivityNotFoundException) {
                result.success(false)
            } catch (_: SecurityException) {
                result.success(false)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aliyesha.akshi/system_settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "notificationPermissionStatus" -> result.success(notificationPermissionStatus())
                "markNotificationPermissionRequested" -> {
                    getSharedPreferences(NOTIFICATION_PREFERENCES, MODE_PRIVATE)
                        .edit()
                        .putBoolean(NOTIFICATION_PERMISSION_REQUESTED, true)
                        .apply()
                    result.success(true)
                }
                "openNotificationSettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(
                                Settings.EXTRA_APP_PACKAGE,
                                packageName,
                            ),
                        )
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: SecurityException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun notificationPermissionStatus(): String {
        val notificationsEnabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return if (notificationsEnabled) "allowed" else "notAllowed"
        }

        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted && notificationsEnabled) return "allowed"

        val requested = getSharedPreferences(NOTIFICATION_PREFERENCES, MODE_PRIVATE)
            .getBoolean(NOTIFICATION_PERMISSION_REQUESTED, false)
        return if (requested) "notAllowed" else "notDetermined"
    }

    private fun queryDns(name: String, type: Int, result: MethodChannel.Result) {
        DnsResolver.getInstance().rawQuery(
            null,
            name,
            1,
            type,
            DnsResolver.FLAG_EMPTY,
            mainExecutor,
            CancellationSignal(),
            object : DnsResolver.Callback<ByteArray> {
                override fun onAnswer(answer: ByteArray, rcode: Int) {
                    if (rcode != 0 && rcode != 3) {
                        result.error("dns_error", "DNS returned response code $rcode", null)
                        return
                    }
                    try {
                        result.success(mapOf("records" to parseAnswers(answer, type)))
                    } catch (error: Exception) {
                        result.error("invalid_dns_response", error.message, null)
                    }
                }

                override fun onError(error: DnsResolver.DnsException) {
                    result.error("dns_error", error.message, error.code)
                }
            },
        )
    }

    private fun parseAnswers(packet: ByteArray, expectedType: Int): List<Map<String, Any>> {
        if (packet.size < 12) error("DNS response is too short")
        val questions = uint16(packet, 4)
        val answerCount = uint16(packet, 6)
        var offset = 12
        repeat(questions) {
            offset = skipName(packet, offset)
            offset += 4
            if (offset > packet.size) error("Invalid DNS question")
        }
        val records = mutableListOf<Map<String, Any>>()
        repeat(answerCount) {
            val owner = readName(packet, offset).ifEmpty { "." }
            offset = skipName(packet, offset)
            if (offset + 10 > packet.size) error("Invalid DNS answer")
            val ttl = uint32(packet, offset + 4)
            val type = uint16(packet, offset)
            val recordClass = uint16(packet, offset + 2)
            val dataLength = uint16(packet, offset + 8)
            val dataOffset = offset + 10
            if (dataOffset + dataLength > packet.size) error("Invalid DNS record data")
            if (type == expectedType && recordClass == 1) {
                val data = when (type) {
                    2, 5 -> normalizeName(packet, dataOffset)
                    15 -> normalizeMx(packet, dataOffset, dataLength)
                    else -> packet.copyOfRange(dataOffset, dataOffset + dataLength)
                }
                records += mapOf(
                    "owner" to owner,
                    "type" to type,
                    "ttl" to ttl,
                    "data" to data,
                )
            }
            offset = dataOffset + dataLength
        }
        return records
    }

    private fun normalizeMx(packet: ByteArray, offset: Int, length: Int): ByteArray {
        if (length < 3) error("Invalid MX record")
        val output = ByteArrayOutputStream()
        output.write(packet[offset].toInt())
        output.write(packet[offset + 1].toInt())
        val labels = readName(packet, offset + 2)
        if (labels.isEmpty()) {
            output.write(0)
        } else {
            labels.split('.').forEach { label ->
                val bytes = label.toByteArray(Charsets.UTF_8)
                if (bytes.size > 63) error("Invalid DNS label")
                output.write(bytes.size)
                output.write(bytes)
            }
            output.write(0)
        }
        return output.toByteArray()
    }

    private fun normalizeName(packet: ByteArray, offset: Int): ByteArray {
        val output = ByteArrayOutputStream()
        val name = readName(packet, offset)
        if (name.isEmpty()) {
            output.write(0)
        } else {
            name.split('.').forEach { label ->
                val bytes = label.toByteArray(Charsets.UTF_8)
                if (bytes.size > 63) error("Invalid DNS label")
                output.write(bytes.size)
                output.write(bytes)
            }
            output.write(0)
        }
        return output.toByteArray()
    }

    private fun skipName(packet: ByteArray, start: Int): Int {
        var offset = start
        while (true) {
            if (offset >= packet.size) error("Invalid DNS name")
            val length = packet[offset].toInt() and 0xff
            if (length == 0) return offset + 1
            if (length and 0xc0 == 0xc0) {
                if (offset + 1 >= packet.size) error("Invalid DNS pointer")
                return offset + 2
            }
            offset += 1 + length
        }
    }

    private fun readName(packet: ByteArray, start: Int): String {
        val labels = mutableListOf<String>()
        var offset = start
        var jumps = 0
        while (true) {
            if (offset >= packet.size || jumps++ > 32) error("Invalid DNS name")
            val length = packet[offset].toInt() and 0xff
            if (length == 0) break
            if (length and 0xc0 == 0xc0) {
                if (offset + 1 >= packet.size) error("Invalid DNS pointer")
                offset = ((length and 0x3f) shl 8) or (packet[offset + 1].toInt() and 0xff)
                continue
            }
            val end = offset + 1 + length
            if (end > packet.size) error("Invalid DNS label")
            labels += packet.copyOfRange(offset + 1, end).toString(Charsets.UTF_8)
            offset = end
        }
        return labels.joinToString(".")
    }

    private fun uint16(bytes: ByteArray, offset: Int): Int {
        if (offset + 1 >= bytes.size) error("Invalid DNS integer")
        return ((bytes[offset].toInt() and 0xff) shl 8) or
            (bytes[offset + 1].toInt() and 0xff)
    }

    private fun uint32(bytes: ByteArray, offset: Int): Long {
        if (offset + 3 >= bytes.size) error("Invalid DNS integer")
        return ((bytes[offset].toLong() and 0xff) shl 24) or
            ((bytes[offset + 1].toLong() and 0xff) shl 16) or
            ((bytes[offset + 2].toLong() and 0xff) shl 8) or
            (bytes[offset + 3].toLong() and 0xff)
    }

    private companion object {
        const val NOTIFICATION_PREFERENCES = "akshi_notification_permissions"
        const val NOTIFICATION_PERMISSION_REQUESTED = "requested"
    }
}
