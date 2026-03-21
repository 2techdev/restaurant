# GastroCore POS – ProGuard / R8 Rules
# Flutter handles most obfuscation via its own build system.
# These rules protect native integrations and third-party SDKs.

# -----------------------------------------------------------------------
# Flutter / Dart
# -----------------------------------------------------------------------
# Flutter engine classes must not be stripped
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.view.** { *; }
-dontwarn io.flutter.**

# -----------------------------------------------------------------------
# Kotlin & Coroutines
# -----------------------------------------------------------------------
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**

# -----------------------------------------------------------------------
# SQLite / Drift ORM
# -----------------------------------------------------------------------
# Keep SQLite JNI bindings (sqlite3_flutter_libs)
-keep class com.almworks.sqlite4java.** { *; }
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**

# -----------------------------------------------------------------------
# MyPOS SDK (slavesdk2.1.8.aar)
# -----------------------------------------------------------------------
-keep class com.mypos.** { *; }
-keep class com.mypos.slavesdk.** { *; }
-dontwarn com.mypos.**

# -----------------------------------------------------------------------
# Wallee / Payment terminal SDKs
# -----------------------------------------------------------------------
-keep class com.wallee.** { *; }
-dontwarn com.wallee.**

# -----------------------------------------------------------------------
# Bluetooth (used for receipt printers & terminals)
# -----------------------------------------------------------------------
-keep class android.bluetooth.** { *; }

# -----------------------------------------------------------------------
# USB Host (USB receipt printers)
# -----------------------------------------------------------------------
-keep class android.hardware.usb.** { *; }

# -----------------------------------------------------------------------
# AndroidX
# -----------------------------------------------------------------------
-keep class androidx.** { *; }
-dontwarn androidx.**

# GridLayout (used by MyPOS SDK dependency)
-keep class androidx.gridlayout.** { *; }

# -----------------------------------------------------------------------
# JSON serialization (json_annotation / json_serializable)
# -----------------------------------------------------------------------
# Keep all classes with @JsonSerializable annotations
-keepattributes *Annotation*
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# -----------------------------------------------------------------------
# Crash reporting / stack traces
# -----------------------------------------------------------------------
# Preserve line numbers for meaningful stack traces in crash reports
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# -----------------------------------------------------------------------
# General Android
# -----------------------------------------------------------------------
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepnames class * implements java.io.Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    !private <fields>;
    !private <methods>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# -----------------------------------------------------------------------
# BootReceiver (currently disabled, keep for future kiosk mode)
# -----------------------------------------------------------------------
-keep class com.gastrocore.gastrocore_pos.BootReceiver { *; }
