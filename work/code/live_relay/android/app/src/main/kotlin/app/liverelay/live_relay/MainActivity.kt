package app.liverelay.live_relay

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private var deviceFactors: DeviceFactorChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceFactors?.close()
        deviceFactors = DeviceFactorChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onStop() {
        deviceFactors?.cancelOperation()
        super.onStop()
    }

    override fun onDestroy() {
        deviceFactors?.close()
        deviceFactors = null
        super.onDestroy()
    }
}
