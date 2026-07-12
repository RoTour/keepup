# OpenRouter is an adapter, and the port is where the rules live

Grading is not a context — the LLM sits behind a driven port *inside* Delivery, because every meaningful state of an Evaluation is a Trainer act ([ADR-0002](./0002-the-llm-proposes-the-trainer-releases.md)). This decides what runs behind that port and why the port exists at all.

`ILlmGrader` takes the frozen Criteria and the submission text, and returns a domain `ProposedGrading`. **No provider type crosses it**: no chat-completion request object, no tool-call struct, no SDK class, no HTTP status. ArchUnit enforces that. Behind it sits **OpenRouter** — OpenAI-compatible chat completions, with one pinned, known-good tool-calling model.

## This is the adapter where three ADRs land at once

It is not a thin HTTP client, and treating it as one is the failure mode.

- **[ADR-0011](./0011-prompt-injection-is-contained-not-prevented.md) — containment.** Criteria go in the system prompt. The submission goes in a delimited, explicitly-untrusted user turn. **Exactly one submission per call, never batched** — batching is an exfiltration vector, it is a hard rule, and it is contract-tested *here*, because here is the only place it can be violated.
- **[ADR-0007](./0007-a-verdict-must-quote-the-learners-own-words.md) — verbatim evidence.** A *met* Verdict must quote the Learner's own words, and that is checked mechanically, in the adapter: evidence must occur in the submission after whitespace and case normalisation; exactly one Verdict per Criterion; Criterion ids matching the frozen copy. Non-conforming output is retried **once**, then abandoned.
- **Forced structured output.** `tool_choice` pinned to the function, `provider.require_parameters=true`, text content ignored entirely. Model output is never parsed as prose.

So the adapter is where an untrusted, non-deterministic, occasionally-hostile text channel is converted into a domain value the rest of Delivery is entitled to trust. That work belongs on the adapter side of the port for two reasons: it is protocol work — the domain has no opinion about tool calls — and it is the only place it can be tested against real provider variance, with WireMock standing in for the provider while the *real adapter code runs*.

## Why a port, and not just an OpenRouter client

Because swapping the provider is a live possibility, not a hypothetical. OpenRouter is itself an aggregator — changing model is changing a string — but the provider underneath could become a direct Anthropic or OpenAI client, or a locally hosted model, and that decision should cost one adapter.

The validation rules above are **ADR-0007's and ADR-0011's, not OpenRouter's.** They have to survive the swap. The port is what guarantees they do — the same claim [ADR-0008](./0008-both-queue-adapters-are-production-paths.md) makes about the broker and [ADR-0020](./0020-no-context-imports-another.md) makes about the contexts, applied to the one dependency that is both the most likely to change and the most dangerous to get wrong.

## Considered Options

- **Call a provider SDK directly from the use case.** Rejected: an SDK type lands in the application layer, the validation rules end up wherever they were convenient, and ADR-0011's *one submission per call* degrades from a rule with a test into a habit.
- **Spring AI / LangChain4j as the abstraction.** Rejected. It is a port somebody else designed, shaped by the union of what providers offer rather than by what ADR-0007 and ADR-0011 need. Forced `tool_choice`, `provider.require_parameters`, and verbatim-evidence validation would each have to be fought for through a framework's seams. `ILlmGrader` has exactly two concerns and states them in domain words.
- **Bind directly to one provider's API.** Rejected: OpenRouter gives one OpenAI-compatible surface across many models, which is precisely what "pin a known-good tool-calling model, and change it the day it degrades" needs. Behind the port, this choice is invisible to everything but the adapter — which is the argument for making it, and for not caring much about it.

## Consequences

**The `OPENROUTER_API_KEY` is the credential to watch.** It is spendable, it lives in the worker role, and ADR-0011 already accepts that attacker-controlled text reaches the model. Separate keys per environment, with spend caps.

A grading call takes on the order of eight seconds, and the rest of the pipeline is sized off that number: SQS visibility at 120 s ≫ the worst case ([ADR-0003](./0003-the-evaluation-queue-is-at-least-once-and-unordered.md)'s double-grading race), and ADR-0008's fifteen-millisecond cross-region latency argument, which only survives because the operation it is compared against is this slow.

**Model variance fails loudly, not quietly.** If the pinned model starts wrapping prose around its tool call or emitting malformed arguments, the adapter's validation turns that into *abandoned* Evaluations — visible to the Trainer, recoverable through [ADR-0019](./0019-abandonment-is-a-domain-fact.md)'s retry — rather than into plausible-looking bad grades. That is the whole design intent, and it is why the mechanical checks are not optional.

**Two retry budgets exist and they are not the same.** One in-process retry of a malformed tool call (this ADR, ADR-0007), and the broker's delivery budget (ADR-0019). They fail into the same domain fact and neither knows about the other.

Revoking the key is the M3 demo criterion. The fact that the abandonment path can be demonstrated by unplugging the provider is not a coincidence — it is the point of putting the provider behind a port in the first place.
