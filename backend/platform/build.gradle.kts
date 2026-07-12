plugins {
    id("keepup.java")
    id("keepup.spring-adapter")
}

// Infrastructure only: outbox, notification transport, distributed locking.
// Platform has ZERO domain knowledge — no project(":backend:contexts:...") line
// belongs here, ever.
dependencies {
}
