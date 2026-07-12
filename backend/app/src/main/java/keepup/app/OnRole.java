package keepup.app;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.context.annotation.Conditional;

/**
 * Registers the annotated bean only when the given runtime role is active.
 *
 * <p>keepup ships as a single Spring Boot artifact that runs as one or more
 * <em>roles</em> — {@code web}, {@code worker}, {@code relay} — chosen at boot by the
 * {@code KEEPUP_ROLES} environment variable (comma-separable, e.g.
 * {@code KEEPUP_ROLES=worker,relay}). A role is a <em>duty</em> the process performs,
 * not the environment it runs in, so it is deliberately NOT a Spring profile
 * (profiles model environments). This custom condition keeps the two concepts apart.
 *
 * <p>Placing this on a bean type or {@code @Bean} method makes that bean exist only in
 * a process whose {@code KEEPUP_ROLES} set contains {@link #value()}.
 *
 * @see OnRoleCondition
 */
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Conditional(OnRoleCondition.class)
public @interface OnRole {

    /** The role that must be active for the annotated bean to be registered. */
    String value();
}
