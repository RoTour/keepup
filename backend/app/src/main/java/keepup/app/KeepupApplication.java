package keepup.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * The composition root of keepup, and the only Spring Boot application in the repo.
 *
 * <p>Every context is wired together here and nowhere else. If a second class in
 * this repo ever grows a {@code main} method, something has gone wrong.
 */
@SpringBootApplication
public class KeepupApplication {

    public static void main(String[] args) {
        SpringApplication.run(KeepupApplication.class, args);
    }
}
