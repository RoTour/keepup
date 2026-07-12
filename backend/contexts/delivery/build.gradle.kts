plugins {
    id("keepup.java")
    id("keepup.spring-adapter")
    // Delivery publishes an abstract contract suite (the queue contract) that any
    // adapter implementation must pass. Test fixtures is how that suite ships.
    `java-test-fixtures`
}

// A bounded context. It may NEVER depend on :backend:contexts:authoring or
// :backend:contexts:identity.
dependencies {
}
