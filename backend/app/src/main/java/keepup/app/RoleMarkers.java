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
 * web. These are intentionally trivial: later slices attach real work to each role.
 */
@Configuration(proxyBeanMethods = false)
class RoleMarkers {

    private static final Logger log = LoggerFactory.getLogger(RoleMarkers.class);

    @Bean
    @OnRole("web")
    ApplicationRunner webRoleMarker() {
        return marker("web");
    }

    @Bean
    @OnRole("worker")
    ApplicationRunner workerRoleMarker() {
        return marker("worker");
    }

    @Bean
    @OnRole("relay")
    ApplicationRunner relayRoleMarker() {
        return marker("relay");
    }

    private static ApplicationRunner marker(String role) {
        return (ApplicationArguments args) -> log.info("role active: {}", role);
    }
}
