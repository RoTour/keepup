package keepup.app;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.mock.env.MockEnvironment;

/**
 * A role is a duty the process performs, chosen at boot by {@code KEEPUP_ROLES}. These
 * tests pin the observable outcome: which {@link OnRole}-guarded beans exist for a given
 * set of active roles, and how the raw {@code KEEPUP_ROLES} string is parsed.
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
    @DisplayName("the active set is trimmed, lower-cased and free of blanks")
    void parsesRawRolesLeniently() {
        // given a messily formatted KEEPUP_ROLES value
        MockEnvironment environment =
                new MockEnvironment().withProperty(OnRoleCondition.ROLES_PROPERTY, " Web , WORKER ,,relay ");

        // when the active roles are parsed
        var activeRoles = OnRoleCondition.activeRoles(environment);

        // then whitespace, case and empty entries are normalised away
        assertThat(activeRoles).containsExactlyInAnyOrder("web", "worker", "relay");
    }

    @Test
    @DisplayName("a blank KEEPUP_ROLES falls back to the default web role")
    void blankRolesFallBackToDefault() {
        // given a KEEPUP_ROLES that is present but blank
        MockEnvironment environment =
                new MockEnvironment().withProperty(OnRoleCondition.ROLES_PROPERTY, "   ");

        // when the active roles are parsed
        var activeRoles = OnRoleCondition.activeRoles(environment);

        // then the process still assumes the default web role
        assertThat(activeRoles).containsExactly(OnRoleCondition.DEFAULT_ROLE);
    }
}
