package keepup.app;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

/**
 * The central choke point: it must abort startup on an unknown role before any bean or
 * condition runs, and stay silent (no throw) for valid or defaulted configurations.
 */
@DisplayName("KEEPUP_ROLES validator (EnvironmentPostProcessor)")
class RolesEnvironmentPostProcessorTest {

    // DeferredLogFactory has a single abstract method; resolve the supplier to a real Log.
    private final RolesEnvironmentPostProcessor processor =
            new RolesEnvironmentPostProcessor(destination -> destination.get());

    @Test
    @DisplayName("an unknown role aborts the boot")
    void unknownRoleAbortsBoot() {
        // given an environment naming an invalid role
        MockEnvironment environment = new MockEnvironment().withProperty(Roles.PROPERTY, "admin");

        // when the environment is post-processed
        // then startup fails fast with a helpful message
        assertThatThrownBy(() -> processor.postProcessEnvironment(environment, null))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("admin")
                .hasMessageContaining("web, worker, relay");
    }

    @Test
    @DisplayName("valid roles pass validation")
    void validRolesPass() {
        // given a valid multi-role environment
        MockEnvironment environment = new MockEnvironment().withProperty(Roles.PROPERTY, "worker,relay");

        // when the environment is post-processed
        // then it does not throw
        assertThatCode(() -> processor.postProcessEnvironment(environment, null)).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("an unset KEEPUP_ROLES passes (default applied)")
    void unsetPasses() {
        // given no KEEPUP_ROLES
        MockEnvironment environment = new MockEnvironment();

        // when the environment is post-processed
        // then it does not throw
        assertThatCode(() -> processor.postProcessEnvironment(environment, null)).doesNotThrowAnyException();
    }
}
