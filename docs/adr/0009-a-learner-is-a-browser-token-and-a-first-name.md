# A Learner is a browser token and a first name

A Learner enters a Session with its Join Code, declares a first name, and the browser holds an opaque token issued by the server. That token is what fetches their feedback and nobody else's. There are no accounts, no passwords, and no email addresses anywhere in the system.

> Scoped by [ADR-0013](./0013-a-trainer-is-a-provisioned-account.md): Trainers do have provisioned accounts with passwords. What remains true system-wide is "no email addresses" — and Learners have no accounts, which is the claim this ADR actually rests on.

> Superseded in part by [ADR-0015](./0015-a-learner-registers-after-their-first-session.md): Learner Accounts exist, registered with a verified school email. What survives — and it is the load-bearing half — is the first minute: Join Code, declared first name, anonymous token, no signup at the door. A Learner's first Session in a Course is still exactly this ADR; from the second, they participate through an account, cross-Session history is no longer unrepresentable, and released feedback survives the tab for whoever registered. "Feedback dies with the tab" below remains true only of anonymous participation.

The Trainer's triage screen shows first names, because the intervention this product exists to enable is a Trainer walking over to Marie at the break. "Learner 17 is lost" is not actionable.

## Considered Options

- **Collect a school email, verify it later.** Rejected. The token already survives a reload, so an email adds nothing to identity — an unverified address is a claim, not a credential, and it *looks* authoritative on screen in a way a first name never does. The one thing an email genuinely buys is feedback that outlives the closed laptop, and that use is exactly the one "verify later" cannot support: a Learner types `marie.dupnt@` instead of `marie.dupont@`, nobody notices, and her answers and grades are mailed to a stranger.
- **Email as a domain-restricted access gate.** Rejected for now. It would be the only option where the address is actually trustworthy, and it stops a Join Code leaking to a group chat — but it puts a magic-link signup flow into the first minute of class, which is precisely what the Join Code exists to avoid.
- **Full anonymity — the Trainer sees "Learner 17".** Rejected, and this is the closest call. A Learner whose name sits on a screen in front of the person grading them writes what they think that person wants to hear, so anonymity here is a data-quality feature and not merely a privacy one. We trade honest answers for an actionable radar, deliberately.

## Consequences

**Feedback dies with the tab.** Close the laptop and the token is gone. A Trainer who Releases a Question after the class has dispersed Releases it to nobody. This is a real limitation and it partly blunts the recovery story in [ADR-0004](./0004-an-evaluation-outlives-its-grading-attempt.md): redriving the dead-letter queue twenty minutes later only helps if people are still in the room.

**The Join Code is the entire access control.** Anyone holding it can join a Session under any first name.

**A first name is unverified.** Two Maries are indistinguishable, and nothing stops "Batman". The Trainer resolves this the way they always have — by looking up.

**There is no cross-Session history.** Progress across a whole training course is not merely unbuilt, it is unrepresentable. That is a deliberate scope boundary.

If this ever needs to grow, the escalation path is email as a *delivery channel* — optional, confirmed, never displayed, feeding an `ILearnerNotifier` port — and not email as an identity.
