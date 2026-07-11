# Delivery

One Quiz, one audience, one point in time. Learners answer, an LLM proposes a grading for each answer, and the Trainer decides what the Learners get to see.

## Language

### Actors

**Trainer**:
The person running the Session. The only actor with authority over a grade.
_Avoid_: Intervenant, Formateur, Instructor, Teacher, Speaker

**Learner**:
A person who joins a Session with its Join Code and answers its questions. Known by a first name they declare themselves, which nobody verifies. Sees feedback on their own answers, and never on anyone else's.
_Avoid_: Student, Participant, Attendee, Apprenant, User

### The run

**Session**:
One live run of a Quiz, with one audience, at one point in time. Owns the Questions and Criteria copied into it at start, and everything the Learners did during the run.
_Avoid_: Quiz, Live, Run, Class, Cours

**Join Code**: 
The short code a Trainer reads out so Learners can enter a Session. It is the only thing standing between a Session and anyone who has it.
_Avoid_: PIN, Access code, Invite, Token

**Question**:
An open-ended prompt, frozen into the Session when it started. Unlike its Authoring counterpart it cannot change. The Trainer opens it, and Learners answer whichever open Question they choose, in whatever order.
_Avoid_: Item, Prompt, Exercise

**Criterion**:
One statement of something a good answer must contain, frozen into the Session when it started. A Submission is graded against its Question's Criteria and nothing else. Learners never see a Criterion until its Question is Closed — a rubric for an open-ended question is an answer key written in advance.
_Avoid_: Rubric, Rule, Expected answer, Correct answer

**Submission**:
One Learner's free-text answer to one Question in one Session. Final the moment it is sent — a Learner drafts freely, but sends once.
_Avoid_: Answer, Response, Réponse

**Evaluation**:
The grading of one Submission, holding exactly one Verdict per Criterion of its Question. It exists from the moment the Submission does, undecided. An LLM proposes a grading, or the attempt is abandoned. Either way, no Learner sees it until the Trainer releases it.
_Avoid_: Score, Grade, Result, Correction, Mark

**Verdict**:
The judgement that one Criterion is, or is not, met by one Submission. There is no middle ground and no partial credit.
_Avoid_: Score, Point, Mark, Rating

**Evidence**:
The span of the Learner's own words that satisfies a Criterion. A Verdict of *met* must carry one, quoted verbatim from the Submission. A Verdict of *not met* carries none.
_Avoid_: Justification, Rationale, Explanation, Reasoning

**Release**:
The Trainer's act of making one graded Evaluation visible to the Learner who earned it. Releases happen as proposals land, without waiting for the Question to close. An undecided Evaluation cannot be released.
_Avoid_: Publish, Reveal, Validate, Approve

**Close**:
The Trainer's act of ending answering on a Question and revealing its Criteria to the Learners who answered it. It both cuts off whoever had not answered yet and hands out the rubric.
_Avoid_: Lock, Finish, Complete, End

**Override**:
The Trainer's own grading of a Submission, standing in place of what the LLM proposed — or supplying one where the LLM's attempt was abandoned. The Trainer's judgement is always final.
_Avoid_: Correct, Amend, Fix, Regrade

**Discard**:
The Trainer's decision that a Question's Evaluations will never be shown to anyone. A Session cannot end until every graded Evaluation has been Released or Discarded. Discarding is a decision; forgetting is not.
_Avoid_: Delete, Drop, Cancel, Skip
