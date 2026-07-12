# The web session lives in Postgres, and the cookie authenticates the socket

[ADR-0013](./0013-a-trainer-is-a-provisioned-account.md) already decided *no JWT*: logging in yields a server-side session cookie. This says where that session is kept, and what else the cookie is asked to do.

**Spring Session JDBC, from M0.** Not "when we scale" — the app runs `web ×2` from the first compose file, and an in-memory `HttpSession` breaks the moment there are two nodes. A Trainer logs in against node A, the proxy sends the next request to node B, and node B has never heard of them. That is not a scaling problem deferred; it is a correctness problem present from the first deploy, and [ADR-0005](./0005-work-queue-and-notification-fan-out-are-different-ports.md) has already rejected the single-replica design that would hide it. The session tables are Flyway-owned with Spring Session's auto-DDL disabled, so drift fails the container at boot rather than mid-class.

**The WebSocket handshake is an HTTP upgrade, so the cookie rides it.** A Trainer's socket and a registered Learner's socket authenticate by exactly the credential their requests already carry. No socket token to mint, no second credential to expire, no revocation dance — the same three words ADR-0013 used, for the same reason. An **anonymous** Learner has no account and no session ([ADR-0009](./0009-a-learner-is-a-browser-token-and-a-first-name.md)); their handshake presents the opaque token instead. Two handshake paths, three principal kinds, one of which is not authenticated in any account sense at all.

CSRF is a cookie token, read by Angular's `HttpClient` and echoed in a header. A cookie-authenticated API needs this; a header-borne JWT would not. That exemption is the entire prize the rejected option offers, and it is not enough.

## Considered Options

- **JWT.** Rejected. It buys statelessness and costs revocation: ADR-0013 makes deactivation an Operator act, and a stateless token stays valid until it expires no matter what the Operator does. The usual answer — short-lived access token plus a refresh token — puts server-side state back and gives it a different name. It is also awkward at exactly the point this design cares about: a browser cannot set an `Authorization` header on a WebSocket handshake, so the socket would need a token-passing dance of its own, which the cookie does for free.
- **Sticky sessions at the reverse proxy** — keep `HttpSession` in memory and let Caddy pin each browser to a node. Rejected. It makes the load balancer part of the correctness argument, and it fails precisely where the system is meant to be strong: killing one web node mid-Session is an M4 gate. With affinity, that kills every session on the node — logged out, mid-class. With Spring Session JDBC, it is a reconnect.
- **An opaque token for everyone, symmetric with the anonymous Learner.** Rejected by ADR-0013 already: a Trainer's world is durable and re-entered across devices and days, which is what a paste-once token is worst at.

## Consequences

Every authenticated request reads a row from the session table. At classroom scale that is a primary-key lookup, and it is also the mechanism that makes deactivation take effect on the next request rather than at token expiry. The cost and the feature are the same line of SQL.

**Session cleanup is a job, and it belongs to the relay role** — the same singleton that owns outbox pruning and session expiry. Spring Session's own scheduled cleanup must not run on `web ×2`.

The socket's life is bounded by the cookie's session. Logging out kills the live triage screen, which is correct, and a reconnect after expiry must land on the login page rather than retrying forever.

The socket layer cannot assume *authenticated* means *has an account*. An anonymous Learner is a first-class principal with a token and no row in Identity, and the handshake code has two paths for as long as ADR-0009's first minute survives.
