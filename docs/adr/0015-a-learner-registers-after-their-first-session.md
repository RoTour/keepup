# A Learner registers after their first Session

The Course record — a Trainer reviewing a whole engagement: which Learner is usually lost, how one Learner fared across weeks — needs an identity that survives cleared browsers, swapped devices, and half a semester. Browser tokens don't, and self-declared first names are claims, not identities. So Learner Accounts exist in v1 — with registration deferred so that the first minute of class stays exactly as [ADR-0009](./0009-a-learner-is-a-browser-token-and-a-first-name.md) built it.

A Learner enters their first Session anonymously: Join Code, declared first name, token. After answering that Session's Questions — same sitting, token still alive — they are prompted to register: a school email and a password, the email verified by confirmation link. ADR-0009's typo argument is undefeated: an unverified `marie.dupnt@` mails her grades to a stranger. Registration **claims** the anonymous participation; the token is the only thread to that work, so a Learner who walks out unregistered leaves an anonymous row that no later account can absorb.

The teeth:

- **One Session of grace per Course.** Joining a Course's second Session requires an account. Optional-forever would make the prompt nagware and leave the Course record permanently holed. A Session outside any Course never requires registration.
- **A Course may restrict Registration to an email domain.** Without it, `batman@gmail.com` verifies just fine — the restriction is what makes "school email" mean something. Optional per Course, so an open workshop still works.

## Considered Options

- **Accounts at the door.** Rejected: a signup flow in the first minute of class is the thing the Join Code exists to prevent, and ADR-0009 already rejected it once for exactly that reason.
- **A Course roster of picked names — identity without accounts.** Rejected as a half-measure. It survives devices fine (the roster is server-side), but names stay unverified, so the moderation and not-their-name problems remain — and accounts were judged inevitable. Better to land the real thing behind a deferred prompt than to build the stepping stone.
- **First-name heuristic across Sessions.** Rejected: two Maries merge, "marie" and "Marie H." split, and the report reads as authoritative while being a guess.
- **A durable browser token.** Rejected: identity dies with cleared site data or a new device — the exact long-course failure this decision exists to prevent.

## Consequences

**Email-sending enters the system** — the `ILearnerNotifier` port ADR-0009 named as the escalation path: verification links now, password resets with it. Learner recovery is self-service by email; [ADR-0013](./0013-a-trainer-is-a-provisioned-account.md)'s Operator-reset clause is Trainer-only. Deliverability to school mail servers becomes an operational concern.

**The first Session is still Batman-grade.** Anonymous entry means moderation begins at week two, never week one. Accepted.

**The longitudinal record is the Trainer's.** The Course radar renders for the Trainer only. What a Learner sees stays scoped as the glossary says: their own answers, nobody else's — never rankings, never the radar.

**Released feedback belongs to the account and survives the tab.** This is the honest registration carrot — "register to keep your feedback" — and it repairs [ADR-0004](./0004-an-evaluation-outlives-its-grading-attempt.md)'s blunted recovery story: a dead-letter queue redriven after the room has dispersed now Releases to people who will see it tonight. Only anonymous first-Session participation still dies with the token.

**ADR-0009 is superseded in part; ADR-0013 is amended.** The first minute survives. "No accounts, no email" does not. Cross-Session history moves from *unrepresentable* to the point of the design.

**The system now holds verified student emails joined to longitudinal performance.** That is data with real weight; a deletion story is owed, no longer optional. Not built in v1 — recorded as debt.
