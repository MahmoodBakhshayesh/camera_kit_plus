package com.abomis.camera_kit_plus

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** CameraKitPlusPlugin */
class CameraKitPlusPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private val listeners = mutableListOf<PluginRegistry.RequestPermissionsResultListener>()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
//    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "camera_kit_plus")

    flutterPluginBinding.platformViewRegistry.registerViewFactory("camera-kit-plus-view", CameraKitPlusViewFactory(flutterPluginBinding.binaryMessenger, this))
    flutterPluginBinding.platformViewRegistry.registerViewFactory("camera-kit-ocr-plus-view", CameraKitOcrPlusViewFactory(flutterPluginBinding.binaryMessenger))

//    channel.setMethodCallHandler(this)
  }

  fun addListener(listener: PluginRegistry.RequestPermissionsResultListener) {
    listeners.add(listener)
  }

  fun removeListener(listener: PluginRegistry.RequestPermissionsResultListener) {
    listeners.remove(listener)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "getPlatformVersion") {
      result.success("Android ${android.os.Build.VERSION.RELEASE}")
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
//    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity()
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivity() {
      listeners.clear()
  }

  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
    for (listener in listeners) {
      if (listener.onRequestPermissionsResult(requestCode, permissions, grantResults)) {
        return true
      }
    }
    return false
  }

}
