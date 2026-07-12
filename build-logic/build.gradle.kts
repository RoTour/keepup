import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    `kotlin-dsl`
}

// CAREFUL — two different Java versions are in play here, and they are not the same thing:
//
//   * The PROJECT compiles to Java 21. That happens in a forked javac from a toolchain
//     JDK that Gradle downloads (see `keepup.java`). Nobody has to install JDK 21.
//
//   * BUILD-LOGIC ITSELF is loaded into the Gradle daemon's JVM as a plugin. Its bytecode
//     must therefore be readable by whatever JDK the daemon happens to run on. Targeting
//     21 here would hard-fail every contributor whose local JDK is < 21 with
//     "Dependency requires at least JVM runtime version 21" — before a single line of
//     project code is compiled.
//
// So build-logic targets 17, the floor Gradle 9 requires of its daemon. This is a
// build-infrastructure detail and has zero bearing on the language level of keepup's
// production code, which is 21.
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}
