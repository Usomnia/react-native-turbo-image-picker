package com.rnturboimagepicker

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

class RNTurboImagePickerPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        android.util.Log.d("RNTurboImagePicker", "getModule called for: $name")
        return if (name == RNTurboImagePickerModule.NAME) {
            RNTurboImagePickerModule(reactContext)
        } else {
            null
        }
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        android.util.Log.d("RNTurboImagePicker", "getReactModuleInfoProvider called")
        return ReactModuleInfoProvider {
            val moduleInfos: MutableMap<String, ReactModuleInfo> = HashMap()
            moduleInfos[RNTurboImagePickerModule.NAME] = ReactModuleInfo(
                RNTurboImagePickerModule.NAME,
                RNTurboImagePickerModule::class.java.name,
                false, // canOverrideExistingModule
                false, // needsEagerInit
                false, // isCxxModule
                true   // isTurboModule
            )
            moduleInfos
        }
    }
}
