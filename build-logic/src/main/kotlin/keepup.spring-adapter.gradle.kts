import org.gradle.api.artifacts.VersionCatalogsExtension

/**
 * keepup.spring-adapter — dependency management for modules that HOST ADAPTERS.
 *
 * Applying this plugin does NOT make a module a Spring module. It only puts the
 * Spring Boot BOM (plus the AWS SDK BOM, which Boot does not manage) on the
 * dependency-management path so adapter code can declare `spring-boot-starter-*`
 * without a version.
 *
 * The ArchUnit ruleset in :backend:app is what actually keeps Spring out of the
 * domain: only classes under `..adapter..` may touch org.springframework,
 * jakarta.persistence, software.amazon.awssdk or com.rabbitmq. The BOM being on
 * the classpath is not a licence to import it.
 */

plugins {
    id("keepup.java")
}

val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

dependencies {
    val springBom = platform(libs.findLibrary("spring-boot-bom").get())
    val awsBom = platform(libs.findLibrary("aws-bom").get())

    "implementation"(springBom)
    "implementation"(awsBom)
    "testImplementation"(springBom)
    "testImplementation"(awsBom)

    // java-test-fixtures modules (currently :backend:contexts:delivery) need the
    // BOM on the fixtures classpath too, or fixtures cannot resolve versionless deps.
    plugins.withId("java-test-fixtures") {
        dependencies {
            "testFixturesImplementation"(springBom)
            "testFixturesImplementation"(awsBom)
        }
    }
}
