// Root build. Deliberately almost empty.
//
// Per-module configuration lives in the convention plugins under build-logic/.
// There is no `allprojects {}` / `subprojects {}` cross-project configuration
// here on purpose: modules opt in to behaviour by applying a `keepup.*` plugin.

plugins {
    base
}
