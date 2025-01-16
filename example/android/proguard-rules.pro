# Prevent obfuscation and stripping of the LineModel and CornerPointModel
-keep class com.your.package.LineModel { *; }
-keep class com.your.package.CornerPointModel { *; }

# Keep Gson annotations and serialized names
-keepattributes *Annotation*
-keepattributes Signature

# Prevent warnings from Gson
-dontwarn com.google.gson.**

# Keep all classes that use Gson serialization
-keep class com.google.gson.** { *; }
