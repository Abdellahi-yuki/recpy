# Flutter-specific rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep app entry point
-keep class io.recpy.app.** { *; }

# Dart/Flutter
-dontwarn io.flutter.**
-keep class com.google.** { *; }
