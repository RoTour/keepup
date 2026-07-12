package keepup.app;

import java.util.Set;
import java.util.stream.Collectors;
import org.apache.commons.logging.Log;
import org.springframework.boot.EnvironmentPostProcessor;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.logging.DeferredLogFactory;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;

/**
 * Validates {@code KEEPUP_ROLES} once, at the earliest point in startup, and announces
 * the resolved role set.
 *
 * <p>This is the central choke point a per-bean {@link OnRoleCondition} cannot be: it
 * runs even when no {@code @OnRole} bean exists, before any condition is evaluated, and
 * fails the boot fast on a typo'd role ({@code wroker}) or an invented one ({@code admin})
 * rather than letting the process come up as a silent no-op. It also logs the roles it
 * resolved at INFO, and WARNs when nothing was named and the default was applied.
 */
public class RolesEnvironmentPostProcessor implements EnvironmentPostProcessor, Ordered {

    private final Log log;

    public RolesEnvironmentPostProcessor(DeferredLogFactory logFactory) {
        this.log = logFactory.getLog(RolesEnvironmentPostProcessor.class);
    }

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        Set<Role> declared = Roles.declared(environment); // throws on an unknown entry -> fail fast
        Set<Role> active = declared.isEmpty() ? Set.of(Roles.DEFAULT) : declared;
        if (declared.isEmpty()) {
            log.warn("KEEPUP_ROLES names no role; defaulting to '" + Roles.display(Roles.DEFAULT)
                    + "'. Set KEEPUP_ROLES to one or more of: " + Roles.validNames());
        }
        log.info("keepup roles active: "
                + active.stream().map(Roles::display).sorted().collect(Collectors.joining(", ")));
    }

    @Override
    public int getOrder() {
        // Run last, after ConfigDataEnvironmentPostProcessor, so a keepup.roles set only in
        // application.yml is already visible when we validate and log.
        return Ordered.LOWEST_PRECEDENCE;
    }
}
