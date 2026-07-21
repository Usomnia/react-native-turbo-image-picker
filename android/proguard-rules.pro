# RNTurboImagePicker ProGuard Rules

# Keep all classes in the package (Module, Package, Activities, etc.)
-keep class com.rnturboimagepicker.** { *; }
-keepclassmembers class com.rnturboimagepicker.** { *; }
-keepnames class com.rnturboimagepicker.** { *; }

# Keep React Native module entry points (loaded via reflection)
-keepclassmembers @com.facebook.react.bridge.ReactModule class * {
    public *;
}

# Keep ReactPackage implementations
-keep class * implements com.facebook.react.ReactPackage { *; }
-keep class * extends com.facebook.react.TurboReactPackage { *; }
-keep class * extends com.facebook.react.BaseReactPackage { *; }

# Keep Activity classes (referenced in AAR's AndroidManifest)
-keep public class com.rnturboimagepicker.*Activity { *; }
-keep public class com.rnturboimagepicker.*Fragment { *; }

# Keep Kotlin companion objects and data classes
-keepclassmembers class com.rnturboimagepicker.** {
    static ** Companion;
    static ** INSTANCE;
}

# Keep Glide (used for image loading inside AAR)
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
    <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
    **[] $VALUES;
    public *;
}

# Prevent R8 from removing classes used only via reflection
-dontwarn com.facebook.proguard.annotations.DoNotStrip
-dontwarn com.facebook.react.**
