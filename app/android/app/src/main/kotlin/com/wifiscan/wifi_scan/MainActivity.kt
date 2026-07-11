package com.wifiscan.wifi_scan

import android.Manifest
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkAddress
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.net.wifi.WifiManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.InetAddress
import java.util.Collections
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.wifiscan/network"
        private const val PERMISSION_REQUEST_CODE = 4101
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNetworkResult: MethodChannel.Result? = null
    private var requestedNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private val commandExecutor = Executors.newCachedThreadPool()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handleMethod(call, result) }
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permissionStatus" -> result.success(permissionStatus())
            "requestPermission" -> requestNetworkPermission(result)
            "networkContext" -> result.success(networkContext())
            "discoverHosts" -> discoverHosts(call, result)
            "currentSsid" -> result.success(currentSsid())
            "connectNetwork" -> connectNetwork(call, result)
            "restoreNetwork" -> restoreNetwork(result)
            else -> result.notImplemented()
        }
    }

    private fun requiredPermission(): String? {
        return when {
            Build.VERSION.SDK_INT >= 37 && applicationInfo.targetSdkVersion >= 37 ->
                "android.permission.ACCESS_LOCAL_NETWORK"
            Build.VERSION.SDK_INT >= 33 -> Manifest.permission.NEARBY_WIFI_DEVICES
            else -> Manifest.permission.ACCESS_FINE_LOCATION
        }
    }

    private fun permissionStatus(): Map<String, Any> {
        val permission = requiredPermission()
        val granted = permission == null || ContextCompat.checkSelfPermission(
            this,
            permission,
        ) == PackageManager.PERMISSION_GRANTED
        return mapOf(
            "granted" to granted,
            "permission" to (permission ?: "none"),
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun requestNetworkPermission(result: MethodChannel.Result) {
        val status = permissionStatus()
        if (status["granted"] == true) {
            result.success(status)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "권한 요청이 이미 진행 중입니다.", null)
            return
        }
        val permission = requiredPermission()
        if (permission == null) {
            result.success(status)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(permission),
            PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        result.success(permissionStatus())
    }

    private fun networkContext(): Map<String, Any?>? {
        val manager = getSystemService(ConnectivityManager::class.java)
        val network = manager.activeNetwork ?: return null
        val properties = manager.getLinkProperties(network) ?: return null
        val address = properties.linkAddresses.firstOrNull { isPrivateIpv4(it) }
            ?: return null
        val ipv4 = address.address.hostAddress ?: return null
        val gateway = properties.routes.firstOrNull {
            it.isDefaultRoute && it.gateway is Inet4Address
        }?.gateway?.hostAddress ?: ""
        val prefix = address.prefixLength
        val networkAddress = ipv4ToInt(ipv4) and maskFor(prefix)
        return mapOf(
            "interfaceName" to (properties.interfaceName ?: "알 수 없음"),
            "ipv4Address" to ipv4,
            "prefixLength" to prefix,
            "gateway" to gateway,
            "scannedNetwork" to intToIpv4(networkAddress),
            "scannedPrefixLength" to minOf(prefix, 24),
        )
    }

    private fun currentSsid(): String? {
        val info = getSystemService(WifiManager::class.java)?.connectionInfo ?: return null
        val ssid = info.ssid?.trim('"') ?: return null
        return if (ssid.isBlank() || ssid == WifiManager.UNKNOWN_SSID) null else ssid
    }

    private fun connectNetwork(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported", "Android 10 이상에서만 앱이 Wi-Fi 연결을 요청할 수 있습니다.", null)
            return
        }
        if (pendingNetworkResult != null) {
            result.error("network_pending", "Wi-Fi 연결 요청이 이미 진행 중입니다.", null)
            return
        }
        val ssid = call.argument<String>("ssid")?.trim().orEmpty()
        val password = call.argument<String>("password").orEmpty()
        if (ssid.isEmpty()) {
            result.error("invalid_ssid", "Wi-Fi 이름이 없습니다.", null)
            return
        }
        val manager = getSystemService(ConnectivityManager::class.java)
        val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (password.isNotEmpty()) builder.setWpa2Passphrase(password)
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(builder.build())
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                requestedNetworkCallback = this
                manager.bindProcessToNetwork(network)
                pendingNetworkResult?.success(true)
                pendingNetworkResult = null
            }

            override fun onUnavailable() {
                pendingNetworkResult?.error("network_unavailable", "Wi-Fi 연결 요청이 거부되었거나 시간 초과되었습니다.", null)
                pendingNetworkResult = null
                requestedNetworkCallback = null
            }
        }
        pendingNetworkResult = result
        requestedNetworkCallback = callback
        manager.requestNetwork(request, callback)
    }

    private fun restoreNetwork(result: MethodChannel.Result) {
        val manager = getSystemService(ConnectivityManager::class.java)
        manager.bindProcessToNetwork(null)
        requestedNetworkCallback?.let { callback ->
            try {
                manager.unregisterNetworkCallback(callback)
            } catch (_: Exception) {
                // The callback may already have been released by Android.
            }
        }
        requestedNetworkCallback = null
        pendingNetworkResult = null
        result.success(true)
    }

    private fun discoverHosts(call: MethodCall, result: MethodChannel.Result) {
        val network = call.argument<String>("network") ?: run {
            result.error("invalid_network", "검색 네트워크가 없습니다.", null)
            return
        }
        val prefix = call.argument<Int>("prefixLength") ?: 24
        val timeout = (call.argument<Int>("timeoutMilliseconds") ?: 250).coerceIn(100, 500)
        val targets = hostTargets(network, prefix).take(254)
        commandExecutor.execute {
            val reachable = Collections.synchronizedList(mutableListOf<String>())
            val workers = Executors.newFixedThreadPool(16)
            try {
                val futures = targets.map { host ->
                    workers.submit {
                        try {
                            if (InetAddress.getByName(host).isReachable(timeout)) {
                                reachable.add(host)
                            }
                        } catch (_: Exception) {
                            // Unreachable hosts are expected during local discovery.
                        }
                    }
                }
                futures.forEach { it.get() }
            } finally {
                workers.shutdownNow()
            }
            runOnUiThread { result.success(reachable.sorted()) }
        }
    }

    private fun isPrivateIpv4(address: LinkAddress): Boolean {
        val value = address.address
        if (value !is Inet4Address) return false
        val bytes = value.address.map { it.toInt() and 0xff }
        return bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] in 16..31) ||
            (bytes[0] == 192 && bytes[1] == 168)
    }

    private fun hostTargets(network: String, prefix: Int): List<String> {
        val boundedPrefix = prefix.coerceIn(24, 32)
        val base = ipv4ToInt(network) and maskFor(boundedPrefix)
        val broadcast = base or maskFor(boundedPrefix).inv()
        return if (boundedPrefix >= 31) {
            listOf(intToIpv4(base))
        } else {
            (base + 1 until broadcast).map(::intToIpv4)
        }
    }

    private fun ipv4ToInt(value: String): Int {
        val bytes = InetAddress.getByName(value).address
        return bytes.fold(0) { total, byte -> (total shl 8) or (byte.toInt() and 0xff) }
    }

    private fun maskFor(prefix: Int): Int {
        if (prefix <= 0) return 0
        if (prefix >= 32) return -1
        return (-1 shl (32 - prefix))
    }

    private fun intToIpv4(value: Int): String {
        return listOf(
            (value ushr 24) and 0xff,
            (value ushr 16) and 0xff,
            (value ushr 8) and 0xff,
            value and 0xff,
        ).joinToString(".")
    }

    override fun onDestroy() {
        getSystemService(ConnectivityManager::class.java).bindProcessToNetwork(null)
        requestedNetworkCallback?.let { callback ->
            try {
                getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(callback)
            } catch (_: Exception) {
                // Cleanup is best effort during activity teardown.
            }
        }
        commandExecutor.shutdownNow()
        super.onDestroy()
    }
}
