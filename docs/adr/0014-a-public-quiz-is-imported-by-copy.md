# A public Quiz is imported by copy

A Trainer can Share a Quiz, making it Public: every Trainer can see it and Import it into their own Collection. Import **copies** the Quiz — questions and criteria — and the copy belongs to the importer entirely: editable, shareable onward, runnable, with nothing linking back but a lineage id. This is the same sentence the whole system says: the copy is the boundary ([ADR-0001](./0001-session-snapshots-its-quiz.md)).

Public exposes the Quiz's content and its owner's Username, and nothing else — never the owner's Sessions or results.

## Considered Options

- **Import as a reference to the owner's Quiz.** Rejected. The importer's Collection stops being theirs: the owner's edit changes what the importer reviewed on Monday before running it on Wednesday, and the owner un-sharing or deleting strands the reference entirely. ADR-0001 already killed this coupling between Authoring and Delivery; recreating it between two Trainers' collections would be the same bug wearing a different hat.
- **Per-Trainer grants — share with a specific colleague.** Rejected: ACL machinery for a provisioned handful. Public/private is binary, and un-sharing is free precisely because imports are copies.
- **Sharing Sessions or results alongside content.** Rejected: a Session is one audience at one point in time and belongs to the Trainer who ran it. Only authored content travels.

## Consequences

Near-identical Quiz copies will exist across Collections. Like ADR-0001 said of Sessions: deliberate, not a normalisation defect, and not to be "fixed" with a foreign key.

**Fixes do not propagate.** The owner correcting a flawed criterion heals nothing already imported; the importer re-imports if they want the fix. That is the price of the importer owning their copy, and it is paid knowingly.

Un-sharing affects future visibility only. Copies already imported are untouched — they were never the owner's to take back.

The act is called **Share**, not Publish — ADR-0002's ban on overloading "publish" across domain and transport applies here too.
