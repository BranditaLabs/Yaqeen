# flutter_local_notifications serialises scheduled notifications with Gson.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
# audio_service / just_audio
-keep class com.ryanheise.** { *; }
# Flutter references Play Core (deferred components) that this app doesn't ship.
-dontwarn com.google.android.play.core.**
# flutter_secure_storage (EncryptedSharedPreferences → Tink).
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
