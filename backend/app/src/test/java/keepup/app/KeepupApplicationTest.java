package keepup.app;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * The composition root must stand up with no database on the classpath: this slice
 * boots web, actuator and the role machinery only. If a future dependency drags in a
 * datasource auto-configuration, this test fails first — which is the intended alarm.
 */
@SpringBootTest
@DisplayName("the keepup application context")
class KeepupApplicationTest {

    @Test
    @DisplayName("loads with the default (web) role and no database")
    void contextLoads() {
        // given the default KEEPUP_ROLES (web)
        // when @SpringBootTest builds the full context
        // then it starts cleanly — the absence of an exception is the assertion
    }
}
