package com.rnturboimagepicker

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReadableMap

abstract class NativeRNTurboImagePickerSpec(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    abstract fun init(licenseKey: String, promise: Promise)
    abstract fun openGallery(options: ReadableMap, promise: Promise)
    abstract fun openViewer(options: ReadableMap, promise: Promise)
    abstract fun openEditor(options: ReadableMap, promise: Promise)
}
