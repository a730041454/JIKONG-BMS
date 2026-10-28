package com.diyi.jikong_bms_app

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "bms/contact"
        const val UPDATE_CHANNEL = "bms/update"
        const val REQ_WRITE = 1101
        const val WECHAT_PKG = "com.tencent.mm"
    }

    private var pendingBytes: ByteArray? = null
    private var pendingName: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "bms_qr"
                        if (bytes == null) {
                            result.error("bad_args", "bytes required", null)
                        } else {
                            saveImage(bytes, name, result)
                        }
                    }
                    "openWeChat" -> {
                        val id = call.argument<String>("id") ?: ""
                        val link = call.argument<String>("link") ?: ""
                        result.success(openWeChat(id, link))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "path required", null)
                        } else {
                            result.success(installApk(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 拉起系统安装界面。返回 ok / permission（已跳到「安装未知应用」设置）/
     * missing（文件不存在）/ fail。
     */
    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) return "missing"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (_: Exception) {
            }
            return "permission"
        }
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            "ok"
        } catch (_: Exception) {
            "fail"
        }
    }

    private fun saveImage(bytes: ByteArray, baseName: String, result: MethodChannel.Result) {
        // Android 10 起写相册走 MediaStore，不需要存储权限
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingBytes = bytes
            pendingName = baseName
            pendingResult = result
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQ_WRITE)
            return
        }
        doSave(bytes, baseName, result)
    }

    private fun doSave(bytes: ByteArray, baseName: String, result: MethodChannel.Result) {
        try {
            val fileName = "${baseName}_${System.currentTimeMillis()}.png"
            val saved: String
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/BMS")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("openOutputStream failed")
                val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                contentResolver.update(uri, done, null, null)
                saved = uri.toString()
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "BMS"
                )
                if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("mkdirs failed")
                val file = File(dir, fileName)
                FileOutputStream(file).use { it.write(bytes) }
                MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("image/png"), null)
                saved = file.absolutePath
            }
            result.success(saved)
        } catch (e: Exception) {
            result.error("save_failed", e.message ?: "save failed", null)
        }
    }

    /**
     * 依次尝试：wxid 聊天页 -> wxid 名片页 -> 自定义链接 -> 微信主界面。
     * weixin:// 必须放最后兜底：微信不接管 https://u.wechat.com 域名，
     * 先试这类链接会被 MIUI「应用双开」解析器拦下并取消启动。
     * 返回 contact（已定位联系人）/ home（只打开微信）/ none（未安装微信）。
     */
    private fun openWeChat(id: String, link: String): String {
        if (packageManager.getLaunchIntentForPackage(WECHAT_PKG) == null) return "none"
        val targets = mutableListOf<Pair<Uri, Boolean>>()
        if (id.isNotBlank()) {
            targets.add(Uri.parse("weixin://dl/chat?$id") to true)
            targets.add(Uri.parse("weixin://contacts/profile/$id") to true)
        }
        if (link.isNotBlank()) targets.add(Uri.parse(link) to true)
        targets.add(Uri.parse("weixin://") to false)
        for ((uri, isContact) in targets) {
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                setPackage(WECHAT_PKG)
            }
            try {
                startActivity(intent)
                return if (isContact) "contact" else "home"
            } catch (_: Exception) {
                // 微信不认这个链接，继续下一种
            }
        }
        return "none"
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_WRITE) return
        val bytes = pendingBytes
        val name = pendingName
        val result = pendingResult
        pendingBytes = null
        pendingName = null
        pendingResult = null
        if (bytes == null || name == null || result == null) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            doSave(bytes, name, result)
        } else {
            result.error("permission_denied", "storage permission denied", null)
        }
    }
}
