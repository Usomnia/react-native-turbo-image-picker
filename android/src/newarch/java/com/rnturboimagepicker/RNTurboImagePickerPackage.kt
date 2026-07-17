package com.rnturboimagepicker.rn

import com.rnturboimagepicker.*

import com.facebook.react.TurboReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider

class RNTurboImagePickerPackage : TurboReactPackage() {
    
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return if (name == RNTurboImagePickerModule.NAME) {
            RNTurboImagePickerModule(reactContext)
        } else {
            null
        }
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider {
            mapOf(
                RNTurboImagePickerModule.NAME to ReactModuleInfo(
                    RNTurboImagePickerModule.NAME,
                    "com.rnturboimagepicker.RNTurboImagePickerModule",
                    false, // canOverrideExistingModule
                    false, // needsEagerInit
                    false, // hasConstants
                    false, // isCxxModule
                    true   // isTurboModule
                )
            )
        }
    }
}

