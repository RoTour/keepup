package keepup.app;

/**
 * A runtime duty performed by the single keepup artifact, selected by {@code KEEPUP_ROLES}.
 *
 * <p>A role is NOT an environment — that is a Spring profile. One process may hold
 * several roles at once (e.g. {@code worker,relay}). This enum is the single source of
 * truth for the valid roles: {@link OnRole} gates beans by it and {@link Roles} validates
 * {@code KEEPUP_ROLES} against it, so a typo cannot slip through as a silent no-op.
 */
public enum Role {

    /** Serves HTTP: controllers and the actuator surface. */
    WEB,

    /** Consumes background work off the queue (e.g. grading jobs). */
    WORKER,

    /** Relays the transactional outbox to the queue / notification fan-out. */
    RELAY
}
