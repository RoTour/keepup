package keepup;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

import com.tngtech.archunit.base.DescribedPredicate;
import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.lang.ArchCondition;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.lang.ConditionEvents;
import com.tngtech.archunit.lang.SimpleConditionEvent;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * The architecture is enforced here or it is not enforced at all.
 *
 * <p>This suite lives in {@code :backend:app} because app is the only module that
 * depends on every context, so {@code importPackages("keepup")} sees the entire
 * system from here. Adding a rule anywhere else would only ever see one module.
 *
 * <p>These rules are load-bearing. They have been proven to fail against planted
 * violations. If you find yourself relaxing one, you are changing the architecture —
 * that is an ADR, not a test edit.
 */
@DisplayName("keepup architecture")
class ArchitectureTest {

    /** Frameworks that must never be visible from domain or application code. */
    private static final String[] INFRASTRUCTURE_PACKAGES = {
        "org.springframework..",
        "jakarta.persistence..",
        "software.amazon.awssdk..",
        "com.rabbitmq..",
    };

    private static final String AUTHORING = "keepup.authoring..";
    private static final String DELIVERY = "keepup.delivery..";
    private static final String IDENTITY = "keepup.identity..";
    private static final String PLATFORM = "keepup.platform..";

    /** Adapters are the ONLY place infrastructure types are allowed to appear. */
    private static final String ADAPTER = "..adapter..";

    /** The house convention for a port: I{Context}{Type} — IQuizRepository, IEvaluationWorkQueue. */
    private static final Pattern PORT_NAME = Pattern.compile("^I[A-Z].*");

    private static JavaClasses keepup;

    @BeforeAll
    static void importProductionClasses() {
        keepup = new ClassFileImporter()
                .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
                .importPackages("keepup");
    }

    // -----------------------------------------------------------------------
    // 1. Domain purity
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("domain and application code depends on no framework — only adapters may")
    void domainIsFreeOfInfrastructure() {
        ArchRule rule = noClasses()
                .that()
                .resideInAnyPackage(AUTHORING, DELIVERY, IDENTITY)
                .and()
                .resideOutsideOfPackage(ADAPTER)
                .should()
                .dependOnClassesThat()
                .resideInAnyPackage(INFRASTRUCTURE_PACKAGES)
                .because(
                        "the domain must be testable without a container and portable across "
                            + "infrastructure; adapters own all protocol-specific logic. "
                            + "keepup.app is exempt — it is Spring by definition.");

        check(rule);
    }

    // -----------------------------------------------------------------------
    // 2. No cross-context imports
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("authoring cannot see delivery or identity")
    void authoringIsSealed() {
        check(contextMustNotSee(AUTHORING, DELIVERY, IDENTITY));
    }

    @Test
    @DisplayName("delivery cannot see authoring or identity")
    void deliveryIsSealed() {
        check(contextMustNotSee(DELIVERY, AUTHORING, IDENTITY));
    }

    @Test
    @DisplayName("identity cannot see authoring or delivery")
    void identityIsSealed() {
        check(contextMustNotSee(IDENTITY, AUTHORING, DELIVERY));
    }

    private static ArchRule contextMustNotSee(String context, String... forbiddenContexts) {
        return noClasses()
                .that()
                .resideInAPackage(context)
                .should()
                .dependOnClassesThat()
                .resideInAnyPackage(forbiddenContexts)
                .because(
                        "bounded contexts are sealed: they integrate through published "
                            + "contracts, never by reaching into each other's model. "
                            + "Only keepup.app may see more than one context.");
    }

    // -----------------------------------------------------------------------
    // 3. Platform has no domain knowledge
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("platform is infrastructure and knows nothing about any context")
    void platformHasNoDomainKnowledge() {
        ArchRule rule = noClasses()
                .that()
                .resideInAPackage(PLATFORM)
                .should()
                .dependOnClassesThat()
                .resideInAnyPackage(AUTHORING, DELIVERY, IDENTITY)
                .because(
                        "platform is a generic technical capability (outbox, notify, lock). "
                            + "The moment it names a domain concept it stops being reusable "
                            + "and becomes a fourth, accidental context.");

        check(rule);
    }

    // -----------------------------------------------------------------------
    // 4. Port naming
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("ports are named I{Context}{Type}")
    void portsFollowTheNamingConvention() {
        ArchRule rule = classes()
                .that()
                .areInterfaces()
                .and()
                .areNotAnnotations()
                // Platform is IN scope: platform exposes ports too (ILockRegistry, ...) and
                // they must not drift onto a different naming convention than the contexts'.
                .and()
                .resideInAnyPackage(AUTHORING, DELIVERY, IDENTITY, PLATFORM)
                .and()
                .resideOutsideOfPackage(ADAPTER)
                .and()
                .areNotAnnotatedWith(FunctionalInterface.class)
                // A `sealed` interface is a domain SUM TYPE (e.g. a Verdict with a fixed set
                // of variants), not a hexagon boundary. Forcing it to be named I... would be
                // wrong. This is the idiomatic Java 21 domain-modelling case, so exempt it.
                .and(DescribedPredicate.not(areSealed()))
                .should(haveAPortName())
                .because(
                        "an interface sitting directly in a feature package IS a port — a "
                            + "boundary of the hexagon — and the house convention names it "
                            + "I{Context}{Type}, e.g. IQuizRepository, IEvaluationWorkQueue. "
                            + "Sealed interfaces (domain sum types), annotations and "
                            + "@FunctionalInterface lambda helpers are NOT ports and are exempt.");

        check(rule);
    }

    /**
     * True for a {@code sealed} interface. ArchUnit 1.4.2 does not model sealedness
     * ({@code JavaModifier} has no SEALED constant, {@code JavaClass} has no
     * {@code isSealed}), so we reflect the actual class and ask {@link Class#isSealed()}.
     * Safe here: the predicate only ever runs against keepup's own interfaces, which are
     * on the test classpath, and the build always runs on JDK 21 where the method exists.
     */
    private static DescribedPredicate<JavaClass> areSealed() {
        return DescribedPredicate.describe("sealed", javaClass -> javaClass.reflect().isSealed());
    }

    /**
     * ArchUnit ships {@code haveSimpleNameStartingWith} but no regex variant for the
     * SIMPLE name ({@code haveNameMatching} matches the fully-qualified name). Starting
     * with "I" is not the rule we want: it would happily accept an interface named
     * {@code Invoice}. So we spell the convention out ourselves.
     */
    private static ArchCondition<JavaClass> haveAPortName() {
        return new ArchCondition<>("have a simple name matching " + PORT_NAME.pattern()) {
            @Override
            public void check(JavaClass port, ConditionEvents events) {
                boolean satisfied = PORT_NAME.matcher(port.getSimpleName()).matches();
                String message = String.format(
                        "%s is an interface in feature package %s, so it is a port, but it is "
                                + "named '%s' which does not match %s",
                        port.getFullName(),
                        port.getPackageName(),
                        port.getSimpleName(),
                        PORT_NAME.pattern());
                events.add(new SimpleConditionEvent(port, satisfied, message));
            }
        };
    }

    // -----------------------------------------------------------------------

    /**
     * The module tree is currently a skeleton, so a rule can legitimately match zero
     * classes. {@code allowEmptyShould(true)} keeps that from being reported as a
     * failure — it does NOT weaken the rule: every rule here has been verified to go
     * red against a planted violation.
     */
    private static void check(ArchRule rule) {
        rule.allowEmptyShould(true).check(keepup);
    }
}
