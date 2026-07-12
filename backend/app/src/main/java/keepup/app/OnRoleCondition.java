package keepup.app;

import java.util.Set;
import org.springframework.context.annotation.Condition;
import org.springframework.context.annotation.ConditionContext;
import org.springframework.core.annotation.MergedAnnotation;
import org.springframework.core.type.AnnotatedTypeMetadata;

/**
 * The {@link Condition} behind {@link OnRole}: registers the bean when the process's
 * active roles intersect the roles the annotation declares.
 *
 * <p>The active set comes from {@link Roles#active(org.springframework.core.env.Environment)},
 * the single source of truth for parsing {@code KEEPUP_ROLES}. Validation of unknown
 * roles is not this condition's job — {@link RolesEnvironmentPostProcessor} already failed
 * the boot before any condition runs — so here matching is a plain set intersection.
 */
public class OnRoleCondition implements Condition {

    @Override
    public boolean matches(ConditionContext context, AnnotatedTypeMetadata metadata) {
        MergedAnnotation<OnRole> annotation = metadata.getAnnotations().get(OnRole.class);
        if (!annotation.isPresent()) {
            return false;
        }
        Role[] declared = annotation.getEnumArray(MergedAnnotation.VALUE, Role.class);
        Set<Role> active = Roles.active(context.getEnvironment());
        for (Role role : declared) {
            if (active.contains(role)) {
                return true;
            }
        }
        return false;
    }
}
