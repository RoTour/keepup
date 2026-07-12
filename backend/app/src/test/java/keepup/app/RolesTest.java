package keepup.app;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

/**
 * Parsing and validation of {@code KEEPUP_ROLES}. Pins the two decisions that matter once
 * {@code @OnRole} gates real infrastructure: default on the empty <em>parsed set</em> (not
 * the blank raw string), and fail fast on an unknown entry.
 */
@DisplayName("KEEPUP_ROLES parsing and validation")
class RolesTest {

    private static MockEnvironment envWith(String rawRoles) {
        return new MockEnvironment().withProperty(Roles.PROPERTY, rawRoles);
    }

    @Test
    @DisplayName("entries are matched case-insensitively, trimmed, in declaration order")
    void parsesEntriesLeniently() {
        // given a messily formatted, mixed-case value
        MockEnvironment environment = envWith(" WEB , Worker ");

        // when the declared roles are parsed
        var declared = Roles.declared(environment);

        // then case and whitespace are normalised away
        assertThat(declared).containsExactly(Role.WEB, Role.WORKER);
    }

    @Test
    @DisplayName("a delimiter-only value names no role, so active resolves to web")
    void delimiterOnlyResolvesToWeb() {
        // given a value of only commas and spaces
        MockEnvironment environment = envWith(" , , ");

        // when declared and active roles are computed
        // then nothing is declared but the default is applied
        assertThat(Roles.declared(environment)).isEmpty();
        assertThat(Roles.active(environment)).containsExactly(Role.WEB);
    }

    @Test
    @DisplayName("an explicitly empty value resolves to web")
    void explicitlyEmptyResolvesToWeb() {
        // given KEEPUP_ROLES set to the empty string
        MockEnvironment environment = envWith("");

        // when active roles are computed
        // then the default web role applies
        assertThat(Roles.active(environment)).containsExactly(Role.WEB);
    }

    @Test
    @DisplayName("an unset value resolves to web")
    void unsetResolvesToWeb() {
        // given no KEEPUP_ROLES at all
        MockEnvironment environment = new MockEnvironment();

        // when active roles are computed
        // then the default web role applies
        assertThat(Roles.active(environment)).containsExactly(Role.WEB);
    }

    @Test
    @DisplayName("an unknown role fails fast with the valid roles named")
    void unknownRoleFailsFast() {
        // given an invented role
        MockEnvironment environment = envWith("admin");

        // when the roles are parsed
        // then it throws, naming the offending entry and the valid set
        assertThatThrownBy(() -> Roles.declared(environment))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("admin")
                .hasMessageContaining("web, worker, relay");
    }

    @Test
    @DisplayName("a typo among valid roles still fails fast")
    void typoFailsFast() {
        // given a misspelled worker alongside a valid role
        MockEnvironment environment = envWith("web,wroker");

        // when the roles are parsed
        // then it throws naming the typo
        assertThatThrownBy(() -> Roles.declared(environment))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("wroker");
    }
}
