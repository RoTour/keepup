pluginManagement {
    repositories {
        gradlePluginPortal()
    }
}

plugins {
    // build-logic is an INCLUDED BUILD: it does not inherit the root settings, so it
    // needs its own toolchain resolver. Without this, `build-logic` cannot find a
    // JDK 21 to compile the convention plugins with and the whole build dies at
    // configuration time on any machine whose local JDK is not 21.
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }

    // Reuse the single source of truth for versions. This makes `libs` available
    // to build-logic's own build script AND (via VersionCatalogsExtension) to the
    // precompiled convention plugins at execution time.
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "build-logic"
