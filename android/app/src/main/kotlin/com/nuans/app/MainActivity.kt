package com.nuans.app

import com.nuans.app.camera.ShadeCameraPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /**
     * Registers the capture plugin.
     *
     * Done by hand because [ShadeCameraPlugin] lives in this application's own
     * sources rather than in a published package, so the generated plugin
     * registrant knows nothing about it. The alternative - publishing the
     * camera layer as a plugin package - buys versioning overhead for a single
     * consumer.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(ShadeCameraPlugin())
    }
}
