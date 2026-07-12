pluginManagement {
    // Convention plugins (keepup.java / keepup.spring-adapter / keepup.archunit)
    includeBuild("build-logic")
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

plugins {
    // Auto-provisions the Java 21 toolchain. The local JDK does not have to be 21 —
    // Gradle downloads a matching JDK on first build. Nobody has to install anything.
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        mavenCentral()
    }
}

rootProject.name = "keepup"

// ---------------------------------------------------------------------------
// The module graph is FROZEN as of slice S0.1. Everything the roadmap needs is
// already here, stubbed. Adding a module later means editing this file, and
// editing this file means a merge conflict for everyone. Don't.
//
//   :backend:contexts:*  bounded contexts. NEVER depend on one another.
//   :backend:platform    infrastructure only. Zero domain knowledge.
//   :backend:app         the composition root. The ONLY Spring Boot application,
//                        and the only module allowed to see more than one context.
// ---------------------------------------------------------------------------
include(":backend:contexts:authoring")
include(":backend:contexts:delivery")
include(":backend:contexts:identity")
include(":backend:platform")
include(":backend:app")
