package keepup.app;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * A role is a duty the process performs, chosen at boot by {@code KEEPUP_ROLES}. These
 * tests pin the observable outcome: which {@link OnRole}-guarded beans exist for a given
 * set of active roles, including the surprising "no real role" inputs and the
 * multi-role (intersection) case.
 */
@DisplayName("@OnRole selects beans by the active KEEPUP_ROLES set")
class OnRoleConditionTest {

    private final ApplicationContextRunner contextRunner =
            new ApplicationContextRunner().withUserConfiguration(RoleMarkers.class);

    @Test
    @DisplayName("a single active role registers only that role's bean")
    void singleRoleRegistersOnlyItsBean() {
        // given a process told to be web only
        contextRunner
                .withPropertyValues("keepup.roles=web")
                // when the context is built
                .run(context ->
                        // then only the web marker exists
                        assertThat(context)
                                .hasBean("webRoleMarker")
                                .doesNotHaveBean("workerRoleMarker")
                                .doesNotHaveBean("relayRoleMarker"));
    }

    @Test
    @DisplayName("a comma-separated set registers every listed role and nothing else")
    void multipleRolesRegisterEachListedBean() {
        // given a process told to be worker and relay
        contextRunner
                .withPropertyValues("keepup.roles=worker,relay")
                // when the context is built
                .run(context ->
                        // then both markers exist and web does not
                        assertThat(context)
                                .hasBean("workerRoleMarker")
                                .hasBean("relayRoleMarker")
                                .doesNotHaveBean("webRoleMarker"));
    }

    @Test
    @DisplayName("with KEEPUP_ROLES unset the process defaults to web alone")
    void defaultsToWebWhenUnset() {
        // given no roles property at all
        contextRunner
                // when the context is built
                .run(context ->
                        // then it behaves as a lone web node
                        assertThat(context)
                                .hasBean("webRoleMarker")
                                .doesNotHaveBean("workerRoleMarker")
                                .doesNotHaveBean("relayRoleMarker"));
    }

    @Test
    @DisplayName("a delimiter-only KEEPUP_ROLES names no role and so defaults to web")
    void delimiterOnlyDefaultsToWeb() {
        // given a value of only commas — no real role
        contextRunner
                .withPropertyValues("keepup.roles=,,,")
                // when the context is built
                .run(context ->
                        // then the default web node behaviour applies
                        assertThat(context)
                                .hasBean("webRoleMarker")
                                .doesNotHaveBean("workerRoleMarker")
                                .doesNotHaveBean("relayRoleMarker"));
    }

    @Test
    @DisplayName("an explicitly empty KEEPUP_ROLES defaults to web")
    void explicitlyEmptyDefaultsToWeb() {
        // given KEEPUP_ROLES set to the empty string
        contextRunner
                .withPropertyValues("keepup.roles=")
                // when the context is built
                .run(context ->
                        // then the default web node behaviour applies
                        assertThat(context)
                                .hasBean("webRoleMarker")
                                .doesNotHaveBean("workerRoleMarker")
                                .doesNotHaveBean("relayRoleMarker"));
    }

    @Test
    @DisplayName("markers are registered as ApplicationRunners")
    void markersAreApplicationRunners() {
        // given all three roles active
        contextRunner
                .withPropertyValues("keepup.roles=web,worker,relay")
                // when the context is built
                .run(context ->
                        // then every marker is an ApplicationRunner bean
                        assertThat(context.getBeansOfType(ApplicationRunner.class))
                                .containsOnlyKeys("webRoleMarker", "workerRoleMarker", "relayRoleMarker"));
    }

    @Test
    @DisplayName("a bean shared by two roles is registered when either is active")
    void sharedBeanMatchesWhenEitherRoleIsActive() {
        ApplicationContextRunner sharedRunner =
                new ApplicationContextRunner().withUserConfiguration(SharedWork.class);

        // given a bean declared for both worker and relay
        // when only worker is active -> present
        sharedRunner
                .withPropertyValues("keepup.roles=worker")
                .run(context -> assertThat(context).hasBean("sharedByWorkerAndRelay"));
        // when only relay is active -> present
        sharedRunner
                .withPropertyValues("keepup.roles=relay")
                .run(context -> assertThat(context).hasBean("sharedByWorkerAndRelay"));
        // when only web is active -> absent (no intersection)
        sharedRunner
                .withPropertyValues("keepup.roles=web")
                .run(context -> assertThat(context).doesNotHaveBean("sharedByWorkerAndRelay"));
    }

    @Configuration(proxyBeanMethods = false)
    static class SharedWork {

        @Bean
        @OnRole({Role.WORKER, Role.RELAY})
        String sharedByWorkerAndRelay() {
            return "shared";
        }
    }
}
