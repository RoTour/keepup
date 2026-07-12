plugins {
    id("keepup.java")
    id("keepup.spring-adapter")
}

// A bounded context. It may NEVER depend on :backend:contexts:authoring or
// :backend:contexts:delivery.
dependencies {
}
