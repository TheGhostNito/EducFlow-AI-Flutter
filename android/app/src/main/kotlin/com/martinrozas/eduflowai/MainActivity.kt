package com.martinrozas.eduflowai

import android.text.format.DateFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val timeFormatChannel = "educflow/time_format"
    private val environmentChannel = "educflow/environment"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            timeFormatChannel
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "uses24HourFormat" -> {
                    result.success(
                        DateFormat.is24HourFormat(this)
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            environmentChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApplicationId" -> result.success(applicationContext.packageName)
                else -> result.notImplemented()
            }
        }
    }
}
