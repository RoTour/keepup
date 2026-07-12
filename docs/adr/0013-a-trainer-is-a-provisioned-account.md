# A Trainer is a provisioned account

Trainers are provisioned by the Operator; there is no signup surface. A Trainer Account is a `TrainerId`, a Username, and a password — deliberately not an email address, so ADR-0009's "no email anywhere in the system" stays true for both actor types. Accounts live in a small supporting Identity context; Authoring and Delivery consume `TrainerId` as opaque identity and never read the account. Logging in yields a server-side session cookie, which also authenticates the WebSocket handshake — no JWT, no revocation dance.

The system is multi-trainer in its data model — `TrainerId` on every Quiz and Session from day one — and single-operator in its administration. Opening signup later is additive, not a migration.

> Amended by [ADR-0015](./0015-a-learner-registers-after-their-first-session.md): Learners now register accounts with a verified school email, so "no email anywhere in the system" no longer holds system-wide, and "email never as identity" is a Trainer-only clause. Trainer identity itself is unchanged: Username, no email, Operator-reset.

## Considered Options

- **Self-service signup: email, password, verification.** Rejected. A signup flow is a whole feature — verification, recovery, abuse handling — serving a population that is a provisioned handful until well past the deadline. Nobody arrives at this product unannounced.
- **OAuth via an external IdP.** Rejected: zero password management, but it puts a third party on the critical path of starting a class, and the demonstration this project exists to produce lies elsewhere.
- **Magic link.** Rejected: drags an email-sending adapter into a system that has none, to serve accounts the Operator creates by hand.
- **Long-lived access key, symmetric with the Learner's token.** Rejected: a Trainer's world is durable and re-entered across devices and days, which is exactly what a paste-once token is bad at — and "I lost my key" reinvents recovery anyway.

## Consequences

**There is no self-service password recovery — by construction.** No email means no reset link. The Operator resets passwords out-of-band. A Trainer who forgets their password is blocked until the Operator intervenes; at this scale the Operator is in the room. Accepted under the same prototype clause as ADR-0008's long-lived credentials.

**Email is expected to arrive eventually** — as a confirmed recovery and delivery channel, never as identity, the same escalation path ADR-0009 reserved for Learners. The Username remains the login handle regardless.

Deactivation is an Operator act: the Trainer can no longer log in, and their data — Quizzes, Sessions, the complete record — survives untouched, keyed by `TrainerId`.

There is no lockout policy. Rate limiting, if any, is an adapter concern; the domain has no rule about failed attempts.
