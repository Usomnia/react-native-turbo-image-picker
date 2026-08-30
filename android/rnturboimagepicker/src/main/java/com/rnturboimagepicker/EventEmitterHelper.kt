package com.rnturboimagepicker

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.Arguments
import com.facebook.react.modules.core.DeviceEventManagerModule
import android.util.Log

object EventEmitterHelper {
    var reactContext: ReactApplicationContext? = null
    
    fun emitViewerWillClose() {
        Log.e("TurboImagePicker", "emitViewerWillClose CALLED! reactContext=" + reactContext)
        try {
            if (reactContext != null) {
                reactContext?.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                    ?.emit("onViewerWillClose", Arguments.createMap())
                Log.e("TurboImagePicker", "EMITTED onViewerWillClose successfully to JS!")
            } else {
                Log.e("TurboImagePicker", "reactContext is NULL! Cannot emit!")
            }
        } catch (e: Exception) {
            Log.e("TurboImagePicker", "EXCEPTION during emit: " + e.message)
            e.printStackTrace()
        }
    }
}
