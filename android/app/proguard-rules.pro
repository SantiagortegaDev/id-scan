# =============================================================================
# ProGuard / R8 rules for ID Scan app
# =============================================================================
# These rules prevent R8 from stripping ML Kit classes loaded via reflection.
# Currently isMinifyEnabled=false in build.gradle.kts, but these rules serve
# as a safety net if minification is re-enabled in the future.
# =============================================================================

# --- ML Kit Barcode Scanning ---
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.mlkit.common.sdkinternal.** { *; }
-keep class com.google.mlkit.** { *; }

# --- Google Play Services (ML Kit dependencies) ---
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.android.gms.internal.** { *; }
-dontwarn com.google.android.gms.internal.**

# --- Keep native method names (ML Kit uses native code) ---
-keepclasseswithmembernames class * {
    native <methods>;
}
