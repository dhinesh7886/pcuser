# Keep all Razorpay classes
-keep class com.razorpay.** { *; }
-keep interface com.razorpay.** { *; }

# Keep Google Pay / Paisa SDK classes
-keep class com.google.android.apps.nbu.paisa.** { *; }

# Keep annotations used for analytics
-keep class proguard.annotation.** { *; }

# Keep classes with reflection
-keep class java.lang.reflect.** { *; }

# Firebase classes (optional if using analytics)
-keep class com.google.firebase.** { *; }

# Keep Parcelable classes
-keep class * implements android.os.Parcelable { *; }

# Keep methods with @Keep annotation
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Keep public classes with public constructors (for SDKs)
-keep public class * {
    public <init>(...);
}

# Keep Play Core classes for Deferred Components
-keep class com.google.android.play.core.** { *; }

# Keep methods called via reflection
-keepclassmembers class * {
    <init>(...);
}