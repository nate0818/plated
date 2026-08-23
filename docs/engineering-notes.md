# Plated — engineering notes

Rules that cost something to learn. Each one is here because it produced a
real bug in this repo, not because it sounds wise.

---

## The proxy substitution

**Answering the question you can see from the proxy nearest to hand, when
the thing itself is available and slightly harder to reach.**

This produced four separate bugs on the elevation branch in a single day,
wearing four different costumes:

| The question | The proxy used | What it cost |
|---|---|---|
| Did the sync work? | `endDate != nil` — it *ended* | A failed sync reported as success |
| Is a sync running? | the start event — did I *witness* it begin | Every already-running sync missed, including failures |
| Where does this claim live? | the file I happened to be diffing | A fixed overclaim left standing in the other file |
| Which drop targets need the fix? | the row type I was looking at | Half the drop targets left broken, on the common path |

A fifth was caught before shipping: registering a watcher on "the line
after the container is constructed" as a proxy for "before any work can
start" — only true if the framework doesn't schedule work inside its own
initialiser, which nothing promises.

Each proxy usually correlates, which is exactly why it survives review.
None of them is the thing being asked about.

**The countermeasure is cheap: after fixing an instance, go find the
class.** Grep for every other call site, every other file the claim lives
in, every other row type. Four of the five above would have been caught by
one grep, and the fifth by asking "is this the thing, or something that
travels with it?"

A verifier on the same branch produced the identical failure from the other
side: a before/after screenshot of the top of a feed standing in for "the
layout is fixed", when the row that mattered was in a lazy container and
was never built. Same substitution.

### It applies to decisions, not just values

The subtlest instance today came from the reviewer, about its own advice.
It priced two failure modes correctly — a phantom costs a slow spinner, a
miss costs a dropped import — and then reasoned about the *remedy* from
the nearest convenient summary of that finding, "bounded cost", instead of
from the mechanism. The mechanism was reinstating a dropped import, which
is not a cost to be bounded at all. Correct analysis, then a proxy for the
analysis when deciding what to do about it.

So the check isn't only "is this value the thing I mean?" but **"am I
acting on the finding, or on my summary of the finding?"** A summary is a
proxy like any other, and the more sensible it sounds the less likely
anyone is to go back and re-read what it was summarising.

## An undefended constant is a value standing in for a reason

Same family. A number picked by feel carries no argument, so nobody can
tell later whether it is still right — and it rots silently.

Two ways this went wrong here, both in one constant:

1. **Felt.** A 60-second expiry that turned out to be simultaneously too
   short and too long. Two failure modes pulling in opposite directions is
   the signature of measuring on the wrong axis — no single value can be
   right, so tuning it only rearranges the wrongness.
2. **Derived-looking.** Replacing it with `activeTimeout * 100` read as
   principled but wasn't: the two quantities have no causal relationship,
   so the multiple was doing all the work and the arithmetic was standing
   in for the reason. It also coupled unrelated numbers, so an unrelated
   UX change would have moved it by a factor nobody intended.

**What actually helps: write the sentence that justifies the number, and
put it next to the number.** If the sentence can't be written, the number
isn't ready. Derive only when the derivation is the real reason.

## Weigh failure modes before balancing them

Before tuning anything that can be wrong in two directions, price both
directions — they are rarely comparable.

The expiry above: too long costs one slow spinner per pull until it clears.
Too short costs a **dropped import** — the app telling a household its data
arrived when it hadn't. Those aren't two sides of a dial to be balanced;
one is a slow gesture and the other is the app lying. Once priced, the
choice ("err long") falls straight out, and the number stops being a
judgement call.
