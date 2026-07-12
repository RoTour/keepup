# Identity

A supporting context. It owns the accounts — who a Trainer or a Learner is when they are neither authoring, grading, nor answering — and issues the `TrainerId` and `LearnerAccountId` the other contexts share. Nothing else lives here.

## Language

### Trainers

**Trainer Account**:
The provisioned record that makes someone a Trainer: a `TrainerId`, a Username, and a credential. One account is one person — an author in Authoring, the authority in Delivery.
_Avoid_: User, Account, Profile, Login

**Username**:
The handle a Trainer presents to log in. A plain name, deliberately not an email address — a Trainer has no email in the system; a Learner does.
_Avoid_: Email, Login, Handle

**Provisioning**:
The Operator's act of creating a Trainer Account, and the only way one comes to exist. There is no Trainer signup.
_Avoid_: Signup, Registration, Onboarding, Invite

**Operator**:
The person who runs the platform and provisions Trainer Accounts. Not an actor inside any Quiz or Session.
_Avoid_: Admin, Administrator, Superuser

### Learners

**Learner Account**:
The account a Learner registers for themselves: a verified school email, a password, and the `LearnerAccountId` a Course's record hangs on. Born by Claiming an anonymous Session participation.
_Avoid_: User, Profile, Student account

**Registration**:
A Learner's act of creating their own Learner Account — deferred by design: prompted after their first Session's Questions, in the same sitting, never at the door. The self-service counterpart of Provisioning.
_Avoid_: Signup, Onboarding, Enrolment

**Claim**:
The step inside Registration that links everything the anonymous token did to the new Learner Account. Possible only while that token lives — an unregistered Learner who leaves, leaves their work behind for good.
_Avoid_: Merge, Link, Attach
