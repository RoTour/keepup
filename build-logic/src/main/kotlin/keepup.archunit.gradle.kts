import org.gradle.api.artifacts.VersionCatalogsExtension

/**
 * keepup.archunit — adds ArchUnit to the test classpath.
 *
 * We use the ArchUnit *core* artifact and drive it from plain JUnit `@Test`
 * methods rather than `archunit-junit5` + `@AnalyzeClasses`. Spring Boot 4.1.0
 * ships JUnit 6, and archunit-junit5 registers its own JUnit Platform TestEngine —
 * the core API sidesteps that engine-compatibility question entirely and costs us
 * nothing but an explicit `rule.check(classes)`.
 */

plugins {
    id("keepup.java")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

dependencies {
    "testImplementation"(libs.findLibrary("archunit").get())
}
