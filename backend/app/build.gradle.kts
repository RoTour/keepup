plugins {
    id("keepup.java")
    id("keepup.spring-adapter")
    id("keepup.archunit")
    alias(libs.plugins.spring.boot)
}

// THE composition root: the only module that may see every context at once, and
// the only Spring Boot application. It is also the only vantage point from which
// ArchUnit can see the whole system — importPackages("keepup") resolves every
// context because they are all on this module's test runtime classpath.
dependencies {
    implementation(project(":backend:contexts:authoring"))
    implementation(project(":backend:contexts:delivery"))
    implementation(project(":backend:contexts:identity"))
    implementation(project(":backend:platform"))

    implementation(libs.spring.boot.starter)
    testImplementation(libs.spring.boot.starter.test)
}
