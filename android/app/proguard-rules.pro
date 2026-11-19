# ML Kit text recognition references optional script models (Chinese,
# Devanagari, Japanese, Korean) that this app does not bundle. Without these
# rules R8 fails release builds with "Missing class ..." errors.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit finds its components by reflection (via the manifest). Renaming or
# removing them makes text recognition fail at runtime with a
# NullPointerException inside ML Kit.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.firebase.components.** { *; }
