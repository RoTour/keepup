package keepup.app;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.context.annotation.Conditional;

/**
 * Registers the annotated bean only when one of the given runtime {@link Role}s is active.
 *
 * <p>keepup ships as a single Spring Boot artifact that runs as one or more roles —
 * {@link Role#WEB}, {@link Role#WORKER}, {@link Role#RELAY} — chosen at boot by the
 * {@code KEEPUP_ROLES} environment variable (comma-separable, e.g.
 * {@code KEEPUP_ROLES=worker,relay}). A role is a <em>duty</em> the process performs, not
 * the environment it runs in, so this is a custom condition, deliberately NOT a Spring
 * profile (profiles model environments).
 *
 * <p>The value is a set: the bean exists when the process's active roles <em>intersect</em>
 * the declared ones. {@code @OnRole(Role.WEB)} is the one-element case; a bean shared by
 * worker and relay is {@code @OnRole({Role.WORKER, Role.RELAY})}.
 *
 * @see OnRoleCondition
 * @see Roles
 */
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Conditional(OnRoleCondition.class)
public @interface OnRole {

    /** Role(s) that activate the bean. Registered when the active set intersects these. */
    Role[] value();
}
