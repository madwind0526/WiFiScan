package com.wifiscan.wifi_scan

import android.Manifest
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkAddress
import android.net.LinkProperties
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
        commandExecutor.shutdownNow()
        super.onDestroy()
    }
}
