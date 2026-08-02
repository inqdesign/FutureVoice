# kotlinx.serialization keeps its generated serializers on the class itself.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.roro.futurevoice.** {
    *** Companion;
}
-keepclasseswithmembers class com.roro.futurevoice.** {
    kotlinx.serialization.KSerializer serializer(...);
}
