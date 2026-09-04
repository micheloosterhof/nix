ABOUTME: Authoring guide for CLAUDE.md — how rules get written, weakened, and merged.
ABOUTME: Read before adding or editing rules. Not deployed; runtime interpretation rules live in CLAUDE.md itself.

# Rule authoring

- A rule should be no more specific or constraining than its intent requires
  (the weakness razor, arXiv:2301.12987: the optimal hypothesis is the weakest,
  not the shortest). Overly specific rules fail on cases nobody foresaw; overly
  strong ones forbid things Michel actually wants.
- Encode the principle that generated a rule, not a patch for the incident that
  prompted it. The incident is one data point; the principle is the weakest
  statement that covers the cases you haven't seen yet.
- Reserve specific hard rules (MUST/NEVER) for recurring hazards where judgment
  has already failed (port changes, sed, pre-commit hooks). Everywhere else,
  state defaults and trust judgment.
- Rule files ratchet toward strength: every incident tempts a new prohibition.
  Before adding a rule, check whether an existing rule's principle already
  covers it. When several specific rules share one principle, merge them into
  the principle plus examples.
- Audit test for any rule: what does it rule out that we actually want ruled
  out? If it rules out more than that, weaken it until intent and extension
  match.
- Place rules by position: instructions at the start and end of a prompt are
  followed best, the middle sags ("lost in the middle"). Lead with identity
  and hard constraints, end with the highest-stakes procedures, park
  low-stakes material in the middle.
- State the desired behavior rather than prohibiting the undesired one;
  negative instructions are followed less reliably. Keep NEVER for hazards
  where the prohibition itself is the point.
- A worked example constrains behavior more reliably than a paragraph of
  description, but surface features get anchored on — label examples as
  illustrative, not exhaustive.
- Every rule is a proxy (Goodhart): when adding one, work out the cheapest
  way to satisfy its letter while violating its intent, and close that path
  in the same rule.
- Rule count is itself a cost: per-rule compliance drops as rules accumulate,
  and conflicting rules degrade even unrelated ones. Prefer merging into an
  existing rule over adding a new one.
- Before a correction becomes a rule, pick its bucket (Vercel's design.md
  triage): judgment goes in prose, reusable mechanics go in a tool,
  template, or config the agent uses, and mechanical failures go in a
  check code enforces (hook, lint, eval test). Prose is the last resort,
  not the default — a rule nothing enforces is the weakest of the three.
- Worked example: "every bugfix needs a failing test first" was too strong.
  The intent was guarding against regression from a distance (the LC_ALL
  export silently defeating LC_TIME), so the rule became: write the test when
  a change elsewhere could break the behavior again; a local, self-evident fix
  needs only the existing tests and a declared triviality judgment.
