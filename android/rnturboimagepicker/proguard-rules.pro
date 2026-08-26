# Add project specific ProGuard rules here.

# Keep TurboModule classes
-keep class com.rnturboimagepicker.** { *; }

# Keep React Native bridge classes
-keepclassmembers class * {
    @com.facebook.react.bridge.ReactMethod <methods>;
}

-keep @com.facebook.react.bridge.ReactModule class * { *; }

# Keep ActivityEventListener implementations
-keep class * implements com.facebook.react.bridge.ActivityEventListener { *; }

# Keep Kotlin metadata
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
-dontwarn java.lang.invoke.StringConcatFactory
-dontwarn com.google.android.material.**
-ignorewarnings
