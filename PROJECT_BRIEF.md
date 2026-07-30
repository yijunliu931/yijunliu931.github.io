# nsa-auditor — Project Brief for AI Assistants

> **Purpose of this document.** This is a self-contained knowledge base about the
> `nsa-auditor` project, written so that an AI assistant can read it once and then
> answer AI-Engineer interview questions on the candidate's behalf — accurately,
> with real numbers, and without overclaiming. Every figure here is verified
> against the actual codebase. When answering, ground each claim in a specific
> fact or number from this document; if something is not covered here, say so
> rather than inventing it. The candidate values honest, evidence-based answers
> over impressive-sounding ones — an interviewer for this kind of role explicitly
> screens out people who "overclaim AI impact without evidence."

---

## 1. One-paragraph summary

`nsa-auditor` is a **neuro-symbolic smart-contract security auditor**: an LLM
agent pipeline proposes vulnerabilities and a **symbolic verifier mathematically
proves them**. The core principle is *LLM proposes, verifier proves* — the LLM is
never trusted to conclude a bug exists; a bug is real only if the verifier
produces a concrete counterexample. It is an open-source reproduction of the core
architecture of CertiK's production AI audit engine, built with open tools
(Halmos symbolic execution replacing CertiK's closed-source CSol verifier) plus
original code. ~1,700 lines of Python, 45 tests, evaluation-driven throughout.

**The candidate is a CertiK engineer who worked on the production engine; this is
an authorized open-source version. The one hard constraint: it may not use the
company's closed verifier (CSol), so it uses the open-source Halmos instead** —
which is precisely why its ceiling on large contracts is lower (explained in §7).

---

## 2. The core idea (the single most important thing to convey)

Most "AI auditing" is an LLM directly reporting bugs — fast and broad, but it
hallucinates, misses things, and gives no proof. This project does **not trust the
LLM's conclusions**:

- **Neural (LLM)** proposes: lists invariants, writes formal specs, judges
  counterexamples. Allowed to be unreliable.
- **Symbolic (Halmos + Z3)** proves: symbolically solves over all inputs, returns
  either a counterexample or a proof.
- **The verifier is the only source of trust.** Every reported vulnerability must
  be confirmed by a mathematical counterexample. Remove the verifier and the
  system degenerates into an LLM guessing.

**Result: very high precision (a finding always carries a mathematical witness),
at the cost of a recall ceiling** (vulnerability classes symbolic execution can't
express are unreachable). In auditing, false positives are very expensive, so this
trade-off is worth it.

### The pipeline (memorize this flow)

```
LLM proposes  →  LLM writes spec  →  Verifier solves  →  LLM judges
 (planner)      (spec_author)       (Halmos, oracle)     (adjudicator)
  neural          neural              symbolic             neural
```

Only the middle step is deterministic. That is deliberate: the trustworthy part
(the verifier) frames the untrustworthy parts (the LLMs).

---

## 3. How counterexamples work (a common interview follow-up)

**The counterexample is produced BY the verifier, not by the LLM.** This direction
matters — it's what makes the system trustworthy.

- The LLM proposes a **safety property** (e.g. "withdraw never pays out more than
  the fair quote").
- The verifier treats function inputs as **symbolic variables**, turns the
  property into a constraint, and hands it to an **SMT solver (Z3)**: "does there
  exist an input where the contract logic holds but the property is violated?"
  - No solution → property proven (no bug within bounds).
  - **Solution found → that solution IS the counterexample** — concrete inputs
    that break the property.

**Real example from this project (`vault-ceil` target):** property = "withdraw
payout ≤ fair quote". Halmos made `shareAmount` and `donation` symbolic, Z3 solved:
`donation=55, shareAmount=4 → pays 32 > fair 31, vault leaks 1 wei`, in 0.32s.
That `(55, 4)` was **solved by Z3, not invented by the LLM**.

This is why it's proof-grade, not test-grade: fuzzing not finding a bug means "the
inputs I tried didn't trigger it"; the verifier not finding one means "proven not
to exist within the bounds."

The LLM's only role around counterexamples is the **adjudicator**: after the
verifier produces a counterexample, an LLM judges whether it's a *real* bug or an
artifact of a mis-stated property / impossible setup. That is denoising, not
verification — the counterexample's existence is already mathematically guaranteed.

---

## 4. Architecture — five components

| Component | File | LLM? | Job | Production analog (CertiK) |
|---|---|---|---|---|
| **Planner** | `nsa/planner.py` | yes | List safety invariants from 4 lenses (MOD/OF/AL/SM) | Stage 1-5 four-dimension planning |
| **SpecAuthor** | `nsa/spec_author.py` | yes | Write each invariant as a Halmos property | Stage 6 spec annotation authoring |
| **Verifier** | `nsa/verifier.py` | **no** | Run Halmos + Z3 to find counterexamples (only deterministic part) | CSol verification |
| **Adjudicator** | `nsa/adjudicator.py` | yes | Judge if a counterexample is a real bug (denoise) | counterexample adjudication |
| **Harness** | `harness/core.py` | no | Cache / resume / isolate / degrade (generic resilience) | isolated workspace runner |

**Data flow:** contract → planner emits invariants (4 dimensions, parallel,
isolated) → for each: spec_author writes property → Halmos solves → if
counterexample, adjudicator judges → findings (deduped by fingerprint).

**Architecture rule, machine-enforced:** `harness/` must NOT import `nsa/` (generic
never depends on specific), enforced by `tests/architecture/test_boundary.py`. The
harness is a domain-agnostic resilience skeleton reusable for any multi-step LLM
pipeline, not just auditing.

---

## 5. What was built (maps directly to AI-Engineer job requirements)

Every item below is real and in the repo. The right column is the interview hook.

| Capability | Where | Interview hook |
|---|---|---|
| **LLM agent pipeline** | `pipeline.py` + 4 components | 4-stage orchestration on a resilience harness |
| **RAG system** | `rag_leg.py` | sentence-transformers + Qdrant vector DB + LLM judge; a *control* leg to compare vs the verifier leg |
| **Evaluation harness** | `eval/score.py` | eval-set as oracle; recall/precision by category/severity; LLM-as-judge + anti-hallucination cross-check |
| **Guardrails** | throughout | verifier-as-oracle, strict JSON + Pydantic, fingerprint dedup |
| **Structured output** | `llm.py` | `messages.parse()` + Pydantic; parse failure → error, never guess |
| **Cost/latency metering** | `meter.py` | token/cost/latency tagged per component; answers "how much does one audit cost" |
| **Production reliability** | `verifier.py`, `harness/core.py` | workspace isolation, timeout degradation, compile self-repair, resume |
| **Async service + dashboard** | `service.py`, `dashboard.html` | FastAPI async scan API, job state machine, live progress, self-contained UI |
| **Deterministic scoping** | `scope.py` | brace-matched function scoping to shrink large contracts for the solver |

Verified stats: ~1,721 lines of Python, 45 tests passing, 57-entry vuln knowledge
base, 9 evaluation targets (6 toy + 3 real benchmark contracts).

---

## 6. Results — HONEST numbers (do not inflate these)

**Toy contracts (6, controlled planted bugs):** recall 0.83, precision 0.83,
~$0.70/contract.

**Real benchmark contracts (3, real production bugs from
multi-agent-scanner-benchmark):**

| Contract | Difficulty | Verifier-leg recall | What happened |
|---|---|---|---|
| idols-refund | 2 | **1.00** | Auth check on `_to` but transfers to `msg.sender` — single call, symbolic `msg.sender` falsifies it directly |
| evergrow | 4 | 0.00 | Halmos runs but counterexamples are false positives (bug needs cross-call state accumulation) |
| idols-staking | 5 | 0.00 | spec_author can't write a compilable property on a contract with external deps |

**The key conclusion is NOT the 0.83.** The method works on real contracts **only
in the easiest tier** — bugs falsifiable by a single call with a symbolic variable
(access control, rounding). Bugs needing **cross-call state accumulation** are
missed. The 0.83 on toys is partly a small-dataset artifact. This boundary was
**quantified and attributed on purpose**, not hidden.

**RAG leg (control system), real contracts:** recall 1/3 (only idols-refund).
See §8 for the retrieval fix that took it from 0/3 to 1/3.

**Two-leg comparison (the project's central empirical claim):** the verifier leg's
trust comes from mathematical proof; the RAG leg's "trust" comes from an LLM
judging retrieval similarity — which is not verifiable (its high precision on toys
was partly an answer-leak the candidate found and fixed). **Coverage comes from
retrieval; trust comes from verification.**

---

## 7. The three walls (why real-contract recall is capped — the most valuable insight)

The candidate attacked real contracts three times; recall stayed near 0 each time,
but each attempt pinned down a different wall. This progression is the strongest
thing to convey in an interview — it demonstrates diagnosis + attribution, not just
building.

1. **Verifier scale wall.** Halmos is *bounded symbolic execution* — it expands the
   call graph into a path tree, so cost grows exponentially with paths; the 1683-line
   evergrow contract causes state explosion. **CertiK's CSol is annotation-based
   modular deductive verification** (a call to function B uses B's annotation instead
   of B's body), so cost grows *linearly* with functions and it doesn't explode. This
   is a tool-paradigm difference, not a tuning problem — and it's the single biggest
   reason the open-source version's recall is capped. CSol is closed-source and not
   available, which is exactly why the open version hits this wall and the production
   engine does not.
2. **spec_author creativity wall.** Semantic bugs require the LLM to *encode the
   attack path into the property* (e.g. construct a duplicate array element, or two
   depositors). On real contracts this is ~10× harder than on toys.
3. **External-dependency wall.** Contracts importing OpenZeppelin/external code:
   spec_author repeatedly writes broken setup → compile failures (idols-staking: 7 of
   12 tasks failed to compile). This one is a fixable engineering gap, not a ceiling.

Attempts that mapped these walls: KG knowledge injection (fixed "planner can't think
of it"); a feedback cycle (proved it's *not* an effort problem — more retries just
amplified noise); the slicer/scope work (right direction, but exposed slice-fidelity
issues). Each wall corresponds to a specific piece of CertiK's production design
(CSol, Stage 1-5 strategy-line decomposition, KG, feedback cycles) — the open version
hitting each wall demonstrates why those production designs are necessary.

---

## 8. Notable engineering stories (use these as concrete interview examples)

Interviewers reward specific incidents over generic claims. These are all real.

- **Eval caught an intermittent architecture bug.** The anchor contract's recall
  suddenly dropped 1.0 → 0.0. A single run would look like "the LLM had a bad day."
  The eval's *stability comparison* revealed an architecture defect: parallel
  verification tasks wrote properties into one shared directory; one task's broken
  intermediate file polluted others' compilation. Fix: isolated workspace per task.
  Lesson: eval doesn't only measure quality, it surfaces defects the eye can't.
- **Found and fixed an eval data leak (self-honesty).** The RAG leg once showed
  precision 1.00 — impressive, but partly an answer leak: the leave-one-out exclusion
  key was derived from the target name (`real-idols-refund` → `"idolsrefund"`) and
  silently failed to match the real KB id (`findings_idols-nft_vf_02`), so a contract's
  own answer ranked #1 in retrieval. Fixed by making the exclusion explicit in
  ground-truth and *failing loudly* if it matches nothing. Re-ran: true RAG recall was
  0/3. Lesson: an LLM-judge's high score can come from leaks you didn't notice.
- **RAG retrieval fix, with before/after numbers.** The RAG leg embedded only the
  contract's first 4000 chars. evergrow's target bug function is at char 35,836 — 9×
  past the cutoff, so it never entered the vector; its answer ranked 30/57. Fix:
  chunk the contract by function (reusing the brace-matcher from `scope.py`), embed
  each chunk, and take the max similarity across chunks (max-pooling). Result: the
  answer's rank went 30 → **1** (sim 0.246 → 0.516); end-to-end RAG recall 0/3 → 1/3.
  The bottleneck then moved *down* to the judge (retrieval now ranks it #1, but the
  judge, seeing the nearest neighbor, decides the pattern doesn't apply). Lesson: fix
  one layer, expose the next.
- **Cost attribution drove optimization.** Metering showed 83% of one audit's cost
  was in spec_author (multi-dimension → ~11 invariants, each writing a property with
  possible retries), only 17% in planner. That told the candidate where to optimize —
  data, not guesswork.
- **Multi-dimension planning, biggest single recall gain.** Splitting the planner
  into 4 lenses (module / operation-flow / asset-lifecycle / state-machine) raised
  recall 0.50 → 0.83. An inflation attack missed by a single lens was caught by the
  asset-lifecycle lens. Not "the model got smarter" — a different viewpoint made the
  bug visible. Embodies the core insight: *auditing is a coverage problem, not an
  intelligence problem.*

---

## 9. Tech stack

Python 3.10+ · Halmos (a16z symbolic execution, Z3 underneath) · Foundry (forge) ·
Claude / Anthropic API (model-agnostic wrapper) · Pydantic v2 · sentence-transformers
(all-MiniLM-L6-v2) · Qdrant (in-memory vector DB) · FastAPI + uvicorn.

Note on the vector DB: Qdrant runs in embedded `:memory:` mode — a pip library, not
a running service; the index is built in RAM per run. The code path is identical if
pointed at a real Qdrant server later (deliberate upgrade seam).

---

## 10. How to answer interview questions with this project

Match the question to a capability (§5) or a story (§8), then answer with a specific
number or incident. Examples:

- **"How do you detect/mitigate hallucinations?"** → The whole architecture: the
  verifier is the oracle; a finding needs a mathematical counterexample, not the
  LLM's opinion. Hallucination is architecturally impossible, not caught after the
  fact. Trade-off: recall ceiling on non-symbolic bugs.
- **"What is evaluation-driven development?"** → eval-set as oracle; the loop is
  *numbers expose a problem → diagnose → fix → numbers verify*. Concrete: the
  recall 1.0→0.0 crash that exposed an architecture bug (§8).
- **"LLM-as-a-judge and its limits?"** → Used it in the scorer with an
  anti-hallucination cross-check (the judged gt_id must actually exist). Lived its
  limit: the RAG precision-1.00 answer-leak (§8).
- **"RAG vs fine-tuning / when each?"** → Built a real two-leg comparison. RAG
  coverage from retrieval, trust from an LLM (unverifiable); verifier trust from
  proof. Chunked-retrieval fix with rank 30→1 numbers (§8).
- **"Manage cost in agent workflows?"** → Per-component metering; 83% in
  spec_author told me where to optimize (§8).
- **"Agent failure / graceful degradation?"** → harness `map` isolates: one task
  fails → records `{ok:false}`, others proceed; solver timeout degrades in ~20s
  instead of hanging.
- **"Tell me about a challenging AI project."** → This project, STAR: honest
  boundary (works on tier-2 bugs, capped on cross-call-state bugs) + the three
  walls (§7) + the eval-caught architecture bug (§8).

**Three rules when answering as this candidate:** (1) every answer lands on a
specific number or incident; (2) proactively state boundaries — this role rewards
"it can't do X because Y" over overclaiming; (3) translate audit jargon into
AI-engineering terms (LLM pipeline / eval / guardrails / RAG / async system), since
the interviewer cares about transferable AI-engineering skill, not smart contracts.

---

## 11. What this project does NOT demonstrate (state these honestly if asked)

- Not proven at production scale / real traffic (the evergrow recall=0 is exactly
  the real-scale limit).
- The verifier leg only reliably catches single-call, symbolically-falsifiable bugs.
- The RAG leg is a simplified control system (basic chunking + max-pooling; no
  re-ranking, hybrid search, or metadata filtering yet).
- No MCP server yet, no distributed tracing/observability beyond cost metering.
