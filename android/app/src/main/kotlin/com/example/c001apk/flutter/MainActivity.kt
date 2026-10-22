package com.example.c001apk.flutter

import android.app.DownloadManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build.VERSION.SDK_INT
import android.os.Build.VERSION_CODES.P
import android.os.Environment
import android.view.Surface
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.webkit.MimeTypeMap;
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/// 自定义刷新率：与 Dart 侧 hive settings box 一致的持久化键名
private const val REFRESH_RATE_FPS_KEY = "refresh_rate_fps"

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "samples.flutter.dev/channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 冷启动回读原生镜像的刷新率选择，供 onWindowFocusChanged 重放
        selectedFps = refreshRatePrefs.getInt(REFRESH_RATE_FPS_KEY, -1).takeIf { it >= 0 }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "getInstalledApps") {
                Thread {
                    result.success(getInstalledApps())
                }.start()
            } else if (call.method == "downloadApk") {
                val url = call.argument<String>("url")
                val name = call.argument<String>("name")
                if (url != null && name != null) {
                    val response = downloadApk(url, name)
                    result.success(response)
                } else {
                    result.success(false)
                }
            } else if (call.method == "exportData") {
                val data = call.argument<String>("data")
                val fileName = call.argument<String>("fileName")
                if (data != null && fileName != null) {
                    exportData = data
                    exportData(fileName)
                }
            } else if (call.method == "getSupportedRefreshRates") {
                result.success(getSupportedRefreshRates())
            } else if (call.method == "setFrameRate") {
                val fps = call.argument<Int>("fps") ?: 0
                selectedFps = fps
                refreshRatePrefs.edit().putInt(REFRESH_RATE_FPS_KEY, fps).apply()
                applyRefreshRate(fps)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    private var exportData: String? = null

    /** 当前选中的刷新率档位；null = 未设置。onWindowFocusChanged 据此重放 */
    private var selectedFps: Int? = null

    /** 原生侧持久化镜像：保证进程死亡后冷启动仍能重放（Dart hive 为 UI 数据源） */
    private val refreshRatePrefs by lazy {
        getSharedPreferences("c001apk_refresh_rate", Context.MODE_PRIVATE)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            selectedFps?.let { applyRefreshRate(it) }
        }
    }

    /** 枚举设备支持的刷新率档位：过滤 55<r<201，去重升序，异常返回空列表 */
    private fun getSupportedRefreshRates(): List<Int> {
        return try {
            val display = display ?: return listOf(60)
            val rates = display.supportedModes
                .map { mode -> Math.round(mode.refreshRate) }
                .filter { rate -> rate > 55 && rate < 201 }
            rates.toSortedSet().toList().ifEmpty { listOf(60) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * 切换刷新率。Android 16 优先路径：
     * 窗口级 preferredRefreshRate（只改刷新率不改分辨率）+ Surface.setFrameRate 官方组合；
     * preferredDisplayModeId 锁最接近档位的 mode 作为兜底。fps=0 时全部清除回系统默认。
     */
    private fun applyRefreshRate(fps: Int) {
        try {
            val attrs = window.attributes
            // 优先路径：窗口级首选刷新率
            attrs.preferredRefreshRate = if (fps > 0) fps.toFloat() else 0f
            // 兜底：把窗口锁到刷新率最接近目标档的显示模式
            val display = display
            attrs.preferredDisplayModeId = if (fps > 0 && display != null) {
                var bestModeId = 0
                var bestDiff = 1000.0f
                for (mode in display.supportedModes) {
                    val diff = Math.abs(mode.refreshRate - fps.toFloat())
                    if (diff < bestDiff) {
                        bestDiff = diff
                        bestModeId = mode.modeId
                    }
                }
                bestModeId
            } else {
                0
            }
            window.attributes = attrs
            // Surface 级帧率提示：递归找到 Flutter 渲染用的 SurfaceView
            val surface = findSurfaceView(window.decorView)?.holder?.surface
            if (surface != null && surface.isValid) {
                surface.setFrameRate(
                    if (fps > 0) fps.toFloat() else 0f,
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ALWAYS
                )
            }
        } catch (e: Exception) {
            // 静默失败，与参考 APK 的 try/catch 行为一致
        }
    }

    /** 递归在 View 树中找 Flutter 的 SurfaceView（FlutterSurfaceView 继承自 SurfaceView） */
    private fun findSurfaceView(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private val backupSAFLauncher =
        registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) backup@{ uri ->
            if (uri == null) return@backup
            try{
                contentResolver.openOutputStream(uri).use { output ->
                    if (output == null)
                        return@backup
                    else if (exportData != null) {
                            output.write(exportData!!.toByteArray())
                            exportData = null
                            Toast.makeText(this, "导出成功", Toast.LENGTH_SHORT).show()
                        }
                    else
                        Toast.makeText(this, "null", Toast.LENGTH_SHORT).show()
                }
            } catch (e: Exception) {
                Toast.makeText(this, e.toString(), Toast.LENGTH_SHORT).show()
            }
    }

    private fun exportData(fileName: String) {
        try {
            backupSAFLauncher.launch(fileName)
        } catch (e: Exception) {
            Toast.makeText(this, e.toString(), Toast.LENGTH_SHORT).show()
        }
    }

    private fun downloadApk(url: String, name: String): Boolean {
        try {
            val mimeType = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(MimeTypeMap.getFileExtensionFromUrl(url))
            val downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val request = DownloadManager
                .Request(Uri.parse(url))
                .setMimeType(mimeType)
                .setTitle(name)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
            if (SDK_INT < 29) {
                request.allowScanningByMediaScanner()
                request.setVisibleInDownloadsUi(true)
            }
            downloadManager.enqueue(request)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun getInstalledApps(): List<Map<String, Any?>> {
        var appList = packageManager.getInstalledApplications(0).filter { info ->
            (info.flags and ApplicationInfo.FLAG_SYSTEM) != ApplicationInfo.FLAG_SYSTEM
        }
        return appList.map { info ->
            val packageInfo = packageManager.getPackageInfo(info.packageName, 0)
            mapOf(
                "icon" to drawableToByteArray(info.loadIcon(packageManager)),
                "appName" to packageManager.getApplicationLabel(info),
                "packageName" to info.packageName,
                "versionName" to packageInfo.versionName,
                "versionCode" to getVersionCode(packageInfo).toString(),
                "lastUpdateTime" to packageInfo.lastUpdateTime.toString(),
            )
        }
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        val bitmap = drawableToBitmap(drawable)
        ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            return stream.toByteArray()
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable) {
            return drawable.bitmap
        }
        val bitmap = Bitmap.createBitmap(
            drawable.intrinsicWidth,
            drawable.intrinsicHeight,
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun getVersionCode(packageInfo: PackageInfo): Long {
        return if (SDK_INT < P) packageInfo.versionCode.toLong()
        else packageInfo.longVersionCode
    }

}
