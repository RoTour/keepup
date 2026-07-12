plugins {
    id("keepup.java")
    id("keepup.spring-adapter")
}

// A bounded context. It may NEVER depend on :backend:contexts:delivery or
// :backend:contexts:identity. There is deliberately no project(...) line below,
// and ArchUnit (see :backend:app) fails the build if one sneaks in via source.
dependencies {
}
