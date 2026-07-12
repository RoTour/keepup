package keepup.app;

import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.core.env.Environment;

/**
 * Parses and validates the process's runtime roles from {@code KEEPUP_ROLES}.
 *
 * <p>The single source of truth for how the environment variable becomes a set of
 * {@link Role}s: read {@code keepup.roles} (Spring's relaxed binding maps the
 * {@code KEEPUP_ROLES} variable onto it), split on commas, trim, drop blanks, match
 * case-insensitively.
 *
 * <p>Two deliberate decisions live here:
 * <ul>
 *   <li><b>Default on the empty parsed set, not the blank string.</b> {@code ",,,"},
 *       {@code "  "} and an unset variable all name zero roles and therefore all resolve
 *       to the single {@link #DEFAULT} role — there is no path where "no real role" runs
 *       nothing.</li>
 *   <li><b>Fail fast on an unknown entry.</b> A typo like {@code wroker} or an invented
 *       {@code admin} throws rather than booting a healthy no-op.</li>
 * </ul>
 */
final class Roles {

    /** Property that {@code KEEPUP_ROLES} binds to via Spring's relaxed binding. */
    static final String PROPERTY = "keepup.roles";

    /** The role assumed when {@code KEEPUP_ROLES} names no valid role. */
    static final Role DEFAULT = Role.WEB;

    private Roles() {}

    /**
     * The roles explicitly named by {@code KEEPUP_ROLES}, in declaration order. May be
     * empty when nothing is named. Throws {@link IllegalStateException} on an unknown entry.
     */
    static Set<Role> declared(Environment environment) {
        Set<Role> roles = new LinkedHashSet<>();
        for (String token : environment.getProperty(PROPERTY, "").split(",")) {
            String candidate = token.trim();
            if (!candidate.isEmpty()) {
                roles.add(parse(candidate));
            }
        }
        return roles;
    }

    /** The active roles: {@link #declared} when any are named, else {@link #DEFAULT} alone. */
    static Set<Role> active(Environment environment) {
        Set<Role> declared = declared(environment);
        return declared.isEmpty() ? Set.of(DEFAULT) : Set.copyOf(declared);
    }

    /** The valid role names, lower-cased and comma-joined — for log and error messages. */
    static String validNames() {
        return Arrays.stream(Role.values()).map(Roles::display).collect(Collectors.joining(", "));
    }

    /** A role's canonical lower-case name, as it appears in {@code KEEPUP_ROLES}. */
    static String display(Role role) {
        return role.name().toLowerCase(Locale.ROOT);
    }

    private static Role parse(String token) {
        for (Role role : Role.values()) {
            if (role.name().equalsIgnoreCase(token)) {
                return role;
            }
        }
        throw new IllegalStateException(
                "Unknown KEEPUP_ROLES entry: '" + token + "'; valid roles are " + validNames());
    }
}
