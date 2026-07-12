package keepup.app;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Proof that the {@link OnRole} mechanism selects beans by runtime role.
 *
 * <p>Each marker is an {@link ApplicationRunner} that logs {@code role active: <role>}
 * on boot, and is registered only for its role. Booting with {@code KEEPUP_ROLES=web}
 * logs the web marker alone; {@code KEEPUP_ROLES=worker,relay} logs those two and not
 * web. This is the M0 "boots in all three roles" proof; later slices attach real work to
 * each role. (The resolved role set is also announced once by
 * {@link RolesEnvironmentPostProcessor} at startup.)
 */
@Configuration(proxyBeanMethods = false)
class RoleMarkers {

    private static final Logger log = LoggerFactory.getLogger(RoleMarkers.class);

    @Bean
    @OnRole(Role.WEB)
    ApplicationRunner webRoleMarker() {
        return marker(Role.WEB);
    }

    @Bean
    @OnRole(Role.WORKER)
    ApplicationRunner workerRoleMarker() {
        return marker(Role.WORKER);
    }

    @Bean
    @OnRole(Role.RELAY)
    ApplicationRunner relayRoleMarker() {
        return marker(Role.RELAY);
    }

    private static ApplicationRunner marker(Role role) {
        return (ApplicationArguments args) -> log.info("role active: {}", Roles.display(role));
    }
}
