package keepup.app;

import java.util.Arrays;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.core.env.Environment;
import org.springframework.core.type.AnnotatedTypeMetadata;

/**
 * The {@link Condition} behind {@link OnRole}: matches when the bean's declared role is
 * one of the roles active in this process.
 *
 * <p>The active set comes from {@code KEEPUP_ROLES}, read through the Spring
 * {@link Environment} as the {@code keepup.roles} property (relaxed binding maps the
 * environment variable onto that name). The value is split on commas; blanks are
 * dropped; comparison is case-insensitive. When the variable is unset the process
 * defaults to a single {@code web} role, so a bare {@code java -jar} boots as a web node.
 */
public class OnRoleCondition implements Condition {

    /** Property name that {@code KEEPUP_ROLES} binds to via Spring's relaxed binding. */
    static final String ROLES_PROPERTY = "keepup.roles";

    /** The role a process assumes when {@code KEEPUP_ROLES} is unset or blank. */
    static final String DEFAULT_ROLE = "web";

    @Override
    public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
        Map<String, Object> attributes = metadata.getAnnotationAttributes(OnRole.class.getName());
        if (attributes == null) {
            return false;
        }
        String requiredRole = normalise((String) attributes.get("value"));
        return activeRoles(context.getEnvironment()).contains(requiredRole);
    }

    /**
     * The roles active in this process, parsed from {@code KEEPUP_ROLES}. Package-visible
     * so the parsing behaviour can be exercised directly.
     */
    static Set<String> activeRoles(Environment environment) {
        String raw = environment.getProperty(ROLES_PROPERTY, DEFAULT_ROLE);
        if (raw.isBlank()) {
            raw = DEFAULT_ROLE;
        }
        return Arrays.stream(raw.split(","))
                .map(OnRoleCondition::normalise)
                .filter(role -> !role.isEmpty())
                .collect(Collectors.toUnmodifiableSet());
    }

    private static String normalise(String role) {
        return role == null ? "" : role.trim().toLowerCase(Locale.ROOT);
    }
}
