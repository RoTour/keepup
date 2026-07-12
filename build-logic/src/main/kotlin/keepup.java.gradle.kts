import org.gradle.api.artifacts.VersionCatalogsExtension

/**
 * keepup.java — the baseline every keepup JVM module applies.
 *
 * Java 21 toolchain (auto-provisioned), JUnit 6 on the platform runner, and a
 * compiler that treats warnings as errors so rot cannot accumulate quietly.
 */

plugins {
    java
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

group = "keepup"
version = "0.1.0-SNAPSHOT"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(libs.findVersion("java").get().requiredVersion.toInt())
    }
}

dependencies {
    // Spring Boot 4.1.0 ships JUnit *6*. Pin the same JUnit BOM everywhere so a
    // module without the Spring BOM (e.g. a pure domain module) cannot silently
    // drift onto a different JUnit than :backend:app runs its tests with.
    "testImplementation"(platform(libs.findLibrary("junit-bom").get()))
    "testImplementation"(libs.findLibrary("junit-jupiter").get())
    "testRuntimeOnly"(libs.findLibrary("junit-platform-launcher").get())
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    options.compilerArgs.addAll(
        listOf(
            // `-processing`: we ship no annotation processors, and javac warns when a
            //   processor path is present but nothing claims an annotation.
            // `-this-escape`: fires when a constructor calls an overridable method. That
            //   is pervasive and idiomatic in Spring @Configuration/@Component classes
            //   (arriving from S0.9 onward) and in adapters. Left on, -Werror would hard-
            //   fail the first adapter and train everyone to reach for @SuppressWarnings.
            //   Dropping it keeps -Werror meaningful for warnings that actually indicate bugs.
            "-Xlint:all,-processing,-this-escape",
            "-Werror",
        ),
    )
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    testLogging {
        events("failed", "skipped")
        showStackTraces = true
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
