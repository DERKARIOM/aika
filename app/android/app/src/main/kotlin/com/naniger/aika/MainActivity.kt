package com.naniger.aika

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File


private const val CHANNEL = "com.naniger.aika/localsend"
private const val REQUEST_CODE_PICK_DIRECTORY = 1
private const val REQUEST_CODE_PICK_DIRECTORY_PATH = 2
private const val REQUEST_CODE_PICK_FILE = 3
private const val WIFI_JOIN_TIMEOUT_MS = 15000

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null

    // Overriding the static methods we need from the Java class, as described
    // in the documentation of `FlutterActivity.NewEngineIntentBuilder`
    companion object {
        fun withNewEngine(): NewEngineIntentBuilder {
            return NewEngineIntentBuilder(MainActivity::class.java)
        }

        fun createDefaultIntent(launchContext: Context): Intent {
            return withNewEngine().build(launchContext)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> {
                    pendingResult = result
                    openDirectoryPicker(onlyPath = false)
                }

                "pickFiles" -> {
                    pendingResult = result
                    openFilePicker()
                }

                "pickDirectoryPath" -> {
                    pendingResult = result
                    openDirectoryPicker(onlyPath = true)
                }

                "createDirectory" -> handleCreateDirectory(call, result)

                "getFileDescriptor" -> handleGetFileDescriptor(call, result)

                "createFile" -> handleCreateFile(call, result)

                "openContentUri" -> {
                    openUri(context, call.argument<String>("uri")!!)
                    result.success(null)
                }

                "openGallery" -> {
                    openGallery()
                    result.success(null)
                }

                "isAnimationsEnabled" -> {
                    result.success(isAnimationsEnabled())
                }

                "startLocalOnlyHotspot" -> startLocalOnlyHotspot(result)

                "stopLocalOnlyHotspot" -> {
                    stopLocalOnlyHotspot()
                    result.success(null)
                }

                "openHotspotSettings" -> {
                    openHotspotSettings()
                    result.success(null)
                }

                "joinWifiNetwork" -> joinWifiNetwork(call, result)

                "unbindWifiNetwork" -> unbindWifiNetwork(result)

                "shareOwnApk" -> shareOwnApk(result)

                else -> result.notImplemented()
            }
        }
    }

    // --- Smart QR Code pairing: local-only Wi-Fi hotspot -------------------------------
    //
    // Used when the device has no Wi-Fi connection at all, so two devices can still pair
    // via the Smart QR Code feature. WifiManager.startLocalOnlyHotspot() (API 26+) is the
    // only Android API that can start a Wi-Fi access point without sending the user to
    // system Settings. It requires a runtime permission (NEARBY_WIFI_DEVICES on Android 13+,
    // ACCESS_FINE_LOCATION below that) declared in AndroidManifest.xml and requested from
    // the Dart side via `permission_handler` before this method is called; on top of the
    // permission grant, some OEMs additionally require system Location services to be
    // turned on for the call to succeed. Both failure modes surface here as onFailed/
    // SecurityException and are reported back to Dart, which falls back to guiding the
    // user to Settings manually.
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null

    private fun startLocalOnlyHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "Local-only hotspot requires Android 8.0 (API 26) or higher", null)
            return
        }

        val existingReservation = hotspotReservation
        if (existingReservation != null) {
            // Already active (e.g. a previous call from this same app session): reuse it
            // instead of asking the system to start a second one.
            result.success(hotspotConfigToMap(existingReservation))
            return
        }

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (wifiManager == null) {
            result.error("UNAVAILABLE", "WifiManager is not available on this device", null)
            return
        }

        // The system only ever calls one of onStarted/onFailed once, but guard against a
        // theoretical double-invocation anyway since MethodChannel.Result.success/error
        // must not be called more than once.
        var resultHandled = false

        try {
            wifiManager.startLocalOnlyHotspot(
                object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                        if (resultHandled) return
                        resultHandled = true
                        hotspotReservation = reservation
                        result.success(hotspotConfigToMap(reservation))
                    }

                    override fun onStopped() {
                        hotspotReservation = null
                    }

                    override fun onFailed(reason: Int) {
                        if (resultHandled) return
                        resultHandled = true
                        hotspotReservation = null
                        result.error("HOTSPOT_FAILED", "startLocalOnlyHotspot failed with reason code $reason", null)
                    }
                },
                Handler(Looper.getMainLooper()),
            )
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Missing permission for startLocalOnlyHotspot", null)
        } catch (e: Exception) {
            result.error("HOTSPOT_FAILED", e.message ?: "Failed to start local-only hotspot", null)
        }
    }

    private fun stopLocalOnlyHotspot() {
        hotspotReservation?.close()
        hotspotReservation = null
    }

    @Suppress("DEPRECATION")
    private fun hotspotConfigToMap(reservation: WifiManager.LocalOnlyHotspotReservation): Map<String, Any?> {
        // SoftApConfiguration (API 30+) replaces the deprecated WifiConfiguration-based
        // getter, but the latter is still functional on older API levels.
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = reservation.softApConfiguration
            mapOf(
                "ssid" to config?.ssid,
                "passphrase" to config?.passphrase,
            )
        } else {
            val config = reservation.wifiConfiguration
            mapOf(
                "ssid" to config?.SSID,
                "passphrase" to config?.preSharedKey,
            )
        }
    }

    private fun openHotspotSettings() {
        try {
            startActivity(Intent("android.settings.TETHER_SETTINGS"))
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
            } catch (e2: Exception) {
                // Nothing more we can do here; the Dart side also shows textual instructions.
            }
        }
    }

    // --- Smart QR Code pairing: auto-join the emitter's local-only hotspot -------------
    //
    // Used on the *scanning* device when the QR payload carries Wi-Fi credentials for a
    // hotspot the emitter just created (see hotspot_helper.dart / qr_pairing_scanner_page.dart).
    // WifiNetworkSpecifier (API 29+) lets the app request a connection to a specific
    // SSID/passphrase without any location permission: unlike the older scan-based Wi-Fi
    // APIs, Android deliberately exempted this "connect to a network you already know" API
    // from ACCESS_FINE_LOCATION/NEARBY_WIFI_DEVICES. It only needs CHANGE_NETWORK_STATE, a
    // normal permission declared in AndroidManifest.xml (auto-granted, no runtime prompt).
    // See https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap.
    //
    // A network requested this way is NOT used for the app's own traffic automatically: it
    // must be explicitly bound via ConnectivityManager.bindProcessToNetwork(), which affects
    // *the whole process*, not just one socket. That binding is undone (bindProcessToNetwork
    // (null) + unregisterNetworkCallback) as soon as the Dart side calls "unbindWifiNetwork"
    // (right after the pairing HTTP call completes), and again defensively in onDestroy(), so
    // the device is never left unable to reach the internet because of a stale binding to an
    // ephemeral hotspot that no longer exists.
    private var wifiNetworkCallback: ConnectivityManager.NetworkCallback? = null

    private fun joinWifiNetwork(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "Programmatic Wi-Fi join requires Android 10 (API 29) or higher", null)
            return
        }

        val ssid = call.argument<String>("ssid")
        val passphrase = call.argument<String>("passphrase")
        if (ssid.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "Missing ssid", null)
            return
        }

        val connectivityManager =
            applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (connectivityManager == null) {
            result.error("UNAVAILABLE", "ConnectivityManager is not available on this device", null)
            return
        }

        // Release any still-pending request from a previous call before starting a new one.
        unbindWifiNetworkInternal(connectivityManager)

        val specifier = try {
            val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
            if (!passphrase.isNullOrEmpty()) {
                builder.setWpa2Passphrase(passphrase)
            }
            builder.build()
        } catch (e: IllegalArgumentException) {
            result.error("JOIN_FAILED", e.message ?: "Invalid SSID or passphrase", null)
            return
        } catch (e: IllegalStateException) {
            result.error("JOIN_FAILED", e.message ?: "Invalid Wi-Fi network specifier", null)
            return
        }

        // A local-only hotspot has no internet capability: without removing that requirement
        // (present by default), the request would never match it.
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        var resultHandled = false
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                super.onAvailable(network)
                if (resultHandled) return
                resultHandled = true
                try {
                    connectivityManager.bindProcessToNetwork(network)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("JOIN_FAILED", e.message ?: "Failed to bind to the joined network", null)
                }
            }

            override fun onUnavailable() {
                super.onUnavailable()
                if (resultHandled) return
                resultHandled = true
                wifiNetworkCallback = null
                result.error("JOIN_FAILED", "Could not connect to the Wi-Fi network", null)
            }
        }
        wifiNetworkCallback = callback

        try {
            connectivityManager.requestNetwork(request, callback, WIFI_JOIN_TIMEOUT_MS)
        } catch (e: Exception) {
            wifiNetworkCallback = null
            result.error("JOIN_FAILED", e.message ?: "Failed to request the Wi-Fi network", null)
        }
    }

    private fun unbindWifiNetwork(result: MethodChannel.Result) {
        val connectivityManager =
            applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (connectivityManager != null) {
            unbindWifiNetworkInternal(connectivityManager)
        }
        result.success(null)
    }

    private fun unbindWifiNetworkInternal(connectivityManager: ConnectivityManager) {
        try {
            connectivityManager.bindProcessToNetwork(null)
        } catch (e: Exception) {
            // Best-effort: nothing more we can do if this fails.
        }
        wifiNetworkCallback?.let {
            try {
                connectivityManager.unregisterNetworkCallback(it)
            } catch (e: Exception) {
                // Already unregistered/invalid — safe to ignore.
            }
        }
        wifiNetworkCallback = null
    }

    override fun onDestroy() {
        stopLocalOnlyHotspot()
        (applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager)?.let {
            unbindWifiNetworkInternal(it)
        }
        super.onDestroy()
    }

    // --- "Partager Aika": share Aika's own installed APK via Android's native Sharesheet ---
    //
    // Lets a user who already has Aika send its APK to a nearby device that doesn't have
    // it yet (e.g. via Bluetooth or Nearby Share), so it can be installed there. Aika never
    // talks to the Bluetooth stack itself: it only resolves its own currently installed
    // APK (name, version, path) via PackageManager — a self-lookup that needs no special
    // permission, unlike enumerating other apps — wraps it in a content:// URI via the
    // FileProvider declared in AndroidManifest.xml, and hands it to Android's own
    // ACTION_SEND chooser. Android itself then presents whatever nearby-sharing targets are
    // actually available on this device (Bluetooth, Nearby Share/Quick Share, etc.); Aika
    // never claims a specific transport is available, since only Android can know that.
    private fun shareOwnApk(result: MethodChannel.Result) {
        try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val packageInfo = pm.getPackageInfo(packageName, 0)
            val apkFile = File(appInfo.sourceDir)
            if (!apkFile.exists()) {
                result.error("APK_NOT_FOUND", "Could not locate Aika's own installed APK file", null)
                return
            }

            val versionName = packageInfo.versionName ?: "?"
            val versionCode: Long = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            }
            val displayName = "Aika-v$versionName.apk"

            val authority = "$packageName.fileprovider"
            val apkUri: Uri = FileProvider.getUriForFile(this, authority, apkFile)

            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/vnd.android.package-archive"
                putExtra(Intent.EXTRA_STREAM, apkUri)
                putExtra(Intent.EXTRA_SUBJECT, displayName)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            val chooser = Intent.createChooser(sendIntent, "Partager Aika").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)

            result.success(
                mapOf(
                    "appName" to pm.getApplicationLabel(appInfo).toString(),
                    "versionName" to versionName,
                    "versionCode" to versionCode,
                    "sizeBytes" to apkFile.length(),
                    "fileName" to displayName,
                )
            )
        } catch (e: Exception) {
            result.error("SHARE_FAILED", e.message ?: "Failed to share Aika's APK", null)
        }
    }

    private fun isAnimationsEnabled() : Boolean {
        return Settings.Global.getFloat(this.getContentResolver(),
            Settings.Global.ANIMATOR_DURATION_SCALE, 1.0f) != 0.0f;
    }

    private fun handleGetFileDescriptor(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString == null) {
            result.error("INVALID_ARGUMENT", "Missing content URI", null)
            return
        }

        val uri = Uri.parse(uriString)
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) {
            result.error("INVALID_ARGUMENT", "Expected a content:// URI", null)
            return
        }

        try {
            val parcelFileDescriptor = contentResolver.openFileDescriptor(uri, "r")
            if (parcelFileDescriptor == null) {
                result.error("OPEN_FAILED", "The content provider did not return a file descriptor", null)
                return
            }

            // Ownership of the detached descriptor is transferred to the caller. It must be
            // closed by Rust (or whichever native consumer receives it) after use.
            parcelFileDescriptor.use {
                result.success(it.detachFd())
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for content URI", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message ?: "Failed to open content URI", null)
        }
    }

    /// Creates a new file inside a SAF directory and opens it for writing.
    ///
    /// Returns the URI of the created document (Android may rename the file on
    /// collisions) and an owned writable file descriptor. The descriptor must be
    /// closed by the native consumer it is passed to.
    private fun handleCreateFile(call: MethodCall, result: MethodChannel.Result) {
        val parentUriString = call.argument<String>("parentUri")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (parentUriString == null || fileName == null) {
            result.error("INVALID_ARGUMENT", "Missing parentUri or fileName", null)
            return
        }

        try {
            val parentUri = Uri.parse(parentUriString)

            // A pure tree URI (content://…/tree/X) must be converted to its
            // document form before it can be used as a parent document.
            val segments = parentUri.pathSegments
            val parentDocumentUri = if (segments.size == 2 && segments[0] == "tree") {
                DocumentsContract.buildDocumentUriUsingTree(
                    parentUri,
                    DocumentsContract.getTreeDocumentId(parentUri)
                )
            } else {
                parentUri
            }

            val documentUri =
                DocumentsContract.createDocument(contentResolver, parentDocumentUri, mimeType, fileName)
            if (documentUri == null) {
                result.error("CREATE_FAILED", "Could not create $fileName in $parentUriString", null)
                return
            }

            val parcelFileDescriptor = contentResolver.openFileDescriptor(documentUri, "w")
            if (parcelFileDescriptor == null) {
                result.error("OPEN_FAILED", "The content provider did not return a file descriptor", null)
                return
            }

            parcelFileDescriptor.use {
                result.success(
                    mapOf(
                        "uri" to documentUri.toString(),
                        "fd" to it.detachFd(),
                    )
                )
            }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message ?: "Permission denied for content URI", null)
        } catch (e: Exception) {
            result.error("CREATE_FAILED", e.message ?: "Failed to create file", null)
        }
    }

    private fun openDirectoryPicker(onlyPath: Boolean) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        startActivityForResult(
            intent,
            if (onlyPath) REQUEST_CODE_PICK_DIRECTORY_PATH else REQUEST_CODE_PICK_DIRECTORY
        )
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra("multi-pick", true)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQUEST_CODE_PICK_FILE)
    }

    @SuppressLint("WrongConstant")
    @Override
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode == Activity.RESULT_CANCELED) {
            pendingResult?.error("CANCELED", "Canceled", null)
            pendingResult = null
            return
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult?.error("Error $resultCode", "Failed to access directory or file", null)
            pendingResult = null
            return
        }

        when (requestCode) {
            REQUEST_CODE_PICK_DIRECTORY -> {
                val uri: Uri? = data.data
                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)

                    val files = mutableListOf<FileInfo>()
                    listFiles(uri, files)
                    val resultData = PickDirectoryResult(uri.toString(), files)
                    pendingResult?.success(resultData.toMap())
                    pendingResult = null
                } else {
                    pendingResult?.error("Error", "Failed to access directory", null)
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_DIRECTORY_PATH -> {
                val uri: Uri? = data.data
                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                if (uri != null) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    pendingResult?.success(uri.toString())
                    pendingResult = null
                } else {
                    pendingResult?.error("Error", "Failed to access directory", null)
                    pendingResult = null
                }
            }

            REQUEST_CODE_PICK_FILE -> {
                val uriList: List<Uri> = when {
                    data.clipData != null -> {
                        val clipData = data.clipData
                        val uris = mutableListOf<Uri>()
                        for (i in 0 until clipData!!.itemCount) {
                            uris.add(clipData.getItemAt(i).uri)
                        }
                        uris
                    }

                    data.data != null -> listOf(data.data!!)
                    else -> {
                        pendingResult?.error("Error", "Failed to access file", null)
                        return
                    }
                }

                val takeFlags: Int =
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

                val resultList = mutableListOf<FileInfo>()
                for (uri in uriList) {
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                    val documentFile = FastDocumentFile.fromDocumentUri(this, uri)
                    if (documentFile == null) {
                        pendingResult?.error("Error", "Failed to access file", null)
                        return
                    }
                    resultList.add(
                        FileInfo(
                            name = documentFile.name,
                            size = documentFile.size,
                            uri = uri.toString(),
                            lastModified = documentFile.lastModified,
                        )
                    )
                }

                pendingResult?.success(resultList.map { it.toMap() })
                pendingResult = null
            }
        }
    }

    private fun listFiles(uri: Uri, files: MutableList<FileInfo>) {
        val pickedDir: FastDocumentFile = FastDocumentFile.fromTreeUri(this, uri)

        for (file in pickedDir.listFiles()) {
            if (file.isDirectory) {
                // Recursive call
                listFiles(file.uri, files)
            } else if (file.isFile) {
                files.add(
                    FileInfo(
                        name = file.name,
                        size = file.size,
                        uri = file.uri.toString(),
                        lastModified = file.lastModified,
                    ),
                )
            }
        }
    }

    @SuppressLint("WrongConstant")
    private fun handleCreateDirectory(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = Uri.parse(call.argument<String>("documentUri")!!)
        val directoryName = call.argument<String>("directoryName")!!

        if (folderExists(documentUri, directoryName)) {
            result.success(null)
            return
        }

        DocumentsContract.createDocument(
            context.contentResolver, documentUri, DocumentsContract.Document.MIME_TYPE_DIR,
            directoryName
        )

        result.success(null)
    }

    private fun folderExists(documentUri: Uri, folderName: String): Boolean {
        var cursor: Cursor? = null
        try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(documentUri, DocumentsContract.getDocumentId(documentUri))
            cursor = contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE
                ),
                null,
                null,
                null,
            )

            if (cursor != null) {
                while (cursor.moveToNext()) {
                    val displayName = cursor.getString(0)
                    val mimeType = cursor.getString(1)

                    if (folderName == displayName && DocumentsContract.Document.MIME_TYPE_DIR == mimeType) {
                        return true
                    }
                }
            }
        } finally {
            cursor?.close()
        }
        return false
    }

    private fun openGallery() {
        val intent = Intent()
        intent.action = Intent.ACTION_VIEW
        intent.type = "image/*"
        startActivity(intent)
    }
}

data class PickDirectoryResult(
    val directoryUri: String,
    val files: List<FileInfo>,
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "directoryUri" to directoryUri,
            "files" to files.map { it.toMap() }
        )
    }
}

data class FileInfo(
    val name: String,
    val size: Long,
    val uri: String,
    val lastModified: Long
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "name" to name,
            "size" to size,
            "uri" to uri,
            "lastModified" to lastModified
        )
    }
}
