# Session snapshots its Quiz at start

A Quiz is authored once and reused across many Sessions, so editing a Quiz must never change what a past Session's scores meant. Starting a Session therefore copies the Quiz's questions and criteria into the Session; `quizId` is retained for lineage only. The evaluation worker grades a Submission against the Session's own frozen copy and never reads a Quiz.

## Considered Options

- **Version the Quiz, pin a version per Session.** Solves the same problem and additionally allows comparing cohorts across revisions of one quiz. Rejected: it requires a draft/published lifecycle and an immutable version store, and nothing yet asks for cross-version comparison.
- **Reference the live Quiz by id.** Rejected: the evaluation worker consumes a Submission seconds after it was written, so a trainer editing a criterion in that window races the grading. Grading would not be reproducible and past scores would silently change meaning.

## Consequences

Question and criterion text is stored twice — once in the Quiz, once in each Session that ran it. This is deliberate. It is not a normalisation defect and should not be "fixed" by replacing the copy with a foreign key.

Session content is frozen when the Session starts. A trainer who spots a typo mid-session cannot correct it in that Session, even on a question nobody has answered yet.
