# =============================================================================
# ProGuard / R8 rules for ID Scan app
# =============================================================================
# These rules prevent R8 from stripping ML Kit classes loaded via reflection.
# Currently isMinifyEnabled=false in build.gradle.kts, but these rules serve
# as a safety net if minification is re-enabled in the future.
# =============================================================================

# --- ML Kit Barcode Scanning ---
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.android.gms.internal.** { *; }
-dontwarn com.google.android.gms.internal.**

# --- ML Kit Text Recognition ---
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.mlkit.common.sdkinternal.** { *; }

# --- ML Kit Core (used by all ML Kit APIs) ---
-keep class com.google.mlkit.** { *; }

# --- Optional script recognizers (not bundled, suppress warnings) ---
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder

# --- Google Play Services / Firebase (ML Kit dependencies) ---
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# --- Keep native method names (ML Kit uses native code) ---
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Keep classes loaded via reflection ---
-keep class * implements com.google.mlkit.common.sdkinternal.ModelManager { *; }
-keep class * implements com.google.mlkit.common.MlKitException { *; }
