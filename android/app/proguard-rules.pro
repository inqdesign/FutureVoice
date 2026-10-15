# kotlinx.serialization keeps its generated serializers on the class itself.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.roro.futurevoice.** {
    *** Companion;
}
-keepclasseswithmembers class com.roro.futurevoice.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Sudachi (Japanese segmentation) builds its plugins by class name from
# sudachi.json, and javax.json finds its provider by name — keep both whole
# for the day minification is switched on.
-keep class com.worksap.nlp.sudachi.** { *; }
-keep class com.worksap.nlp.dartsclone.** { *; }
-keep class org.glassfish.json.** { *; }
-keep class javax.json.** { *; }
-dontwarn com.worksap.nlp.**
-dontwarn javax.json.**
