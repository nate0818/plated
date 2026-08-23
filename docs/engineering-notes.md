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

---

# Carried from the elevation branch

## Prose should be rendered, not stored

`PlatedNotification.body` stores whole sentences with a person's name baked
in — "Me saved Sam's pancakes" — at five sites (PostThreadView:135,
TableFeedView:595/629/727, Notifier:62). `actorName` follows a rename; the
sentence doesn't.

**Visible symptom, so nobody refiles it:** after a first-session rename the
activity feed reads "Me saved Sam's pancakes" until those rows age out.

**Do NOT fix this by rewriting the stored text.** Substring replacement on
prose is unfixable rather than merely risky: a name has no word boundary
you can trust across a household's vocabulary, and you are one surname away
from corrupting a dish title permanently ("Sam" inside "Samosa" is only the
obvious case).

**The reason to defer is not "logs shouldn't be rewritten."** That argument
is right for a genuine rename (Nate → Nathan shouldn't edit history) and
wrong for the case that actually produces this: the bootstrap wrote "Me"
because Apple returned no name, and the user then filled in a blank. There
was never a moment when they were called "Me". Recording the deferral that
way would invite someone to do the dangerous edit.

**Build this instead, when notifications are next touched:** compose the
sentence from `actorName` at display time rather than storing it. Nothing
needs rewriting, the substring hazard never exists, and the "Me" case fixes
itself. Structurally the same move as `PersonRef.author` — remove the
possibility rather than patch the instances.

## Smaller, all with the same shape as things already fixed

- `AskProngsbyIntent:33` / `ProngsbyView:435` — "is the user looking at
  this?" tested via `applicationState == .active`, which is never true on a
  Siri path and is falsified by any system alert. The guard never suppresses.
- `HouseholdHomeView:372` — the household banner has two writers with
  different crop rules; Home silently re-crops what the profile stored.
- `-plated-prongsby-demo` writes durable rows into the shared store,
  contaminating every later run on that simulator (`ProngsbyView:444`).
- Badge contrast 3.87:1 (short of AA 4.5:1); `BadgeMedal`'s progress track
  1.19:1 on light canvas, so the ring can't carry the state it is asked to.
- A fourth false type-floor claim survives in the rewritten §3.
- `HouseholdHomeView:187` main-actor isolation warning.
- The flag contract omits three debug flags, one of which deletes the
  CloudKit zone.
- WeekView's host avatar is the one copy of that control still unlabelled
  for VoiceOver.
- The tab bar's labels crowd at accessibility sizes ("Recipes" and "Home"
  touching) — found on my own AXL screenshot, not by the fleet.

## Known residue, already documented in code

- CloudSync: a live import older than `staleAfter` reads as idle, so its
  completion is dropped and a *failing* one gives a reassuring tap. Needs a
  five-minute live import plus a pull. Measured on device: CloudKit posts
  exactly two events per operation and never re-posts progress, so nothing
  may depend on re-arming.
- `HouseholdIdentity.rename` shares one trailing `try? context.save()`
  across nine rewrites. Assignments don't throw, so there is no torn-write
  path; the open question is what a failed save leaves behind.

## Fix it by doing less

The three rounds that went wrong on the rename all went wrong by *adding*
coverage: each extended the list of fields rewritten, and each desynced
something new or missed a category. The round that went right removed
coverage — reverting the `mentions` rewrite on the grounds that a value
derived from another desyncs by construction if you rewrite only one.

Removal cannot create a new desync. It can only restore a prior state or
fail to. That makes it a categorically safer move than extension, and it
was available every round — nobody reached for it until the fourth.

**"Fix it by doing less" is not a lesser fix.** When a patch round has
already gone wrong twice in the same class, prefer the subtractive option
before the additive one.

**And a rewrite can be lossy in a way that forecloses the proper fix.**
The strongest argument for reverting the `mentions` rewrite is not that it
regressed the styling — it is that it *destroyed information*. With
mentions `["Me"]` the literal token "@Me" still has a matching entry, so a
display-time resolver plus a rename ledger can map old token to current
member. With `["Nate"]` the association between the token and the member
is unrecoverable from the data. The rewrite bought nothing (same wrong
string on screen, styling removed) and cost the deferred fix its inputs.
Before rewriting stored data to "correct" it, ask what the correct version
would have needed.

## The chosen inconsistency inside a single comment

After reverting the `mentions` rewrite, a comment that BOTH replies to the
owner AND mentions them shows the **new** name in the reply chevron
(`replyToName` is still rewritten) and the **old** one in the body. That is
internally inconsistent within one comment, and it is a choice rather than
an oversight:

- `replyToName` is stored standalone and rendered directly — nothing
  matches it against prose, so rewriting it is correct and safe, exactly
  like `taggedNames`.
- `mentions` is derived from the comment text and only decides bolding, so
  rewriting it desyncs the renderer.

So the alternative to the inconsistency is making the chevron stale *too*,
purely for internal consistency — trading one correct element for two
wrong ones. Attribution that is right beats symmetry that is uniformly
wrong. Revisit when mentions render through the member lookup rather than
a frozen token, at which point both become correct and the question
disappears.

## `rollback()` on a shared context is not free

`HouseholdIdentity.rename` calls `context.rollback()` when its save throws.
That context is the **shared mainContext**, so rollback discards *every*
pending change in the app, not just the rename's.

**Can such state exist at that moment? Yes, briefly.** `PlatedApp` attaches
with `.modelContainer(container)`, which leaves autosave enabled, so
pending model edits are normally flushed within a run-loop turn or two —
but a plate toggle (`TableFeedView:584/717`, `DiscoverView:302`) or a
favourite toggle (`CookbookView:597`) made moments before Done can still be
uncommitted when a rename fails. Comment drafts are `@State` strings, not
model objects, so those are unaffected.

The trade is still correct — **a lost plate toggle beats a split identity**
— but the next person to read `rollback()` should not assume it is free.
The scoped version is to do the rename in a child `ModelContext` and merge
on success, so a failure discards only its own work.

## Trim before equality, deliberately

`rename` trims `newName` and *then* compares to the stored name, so adding
a trailing space to your own name is a no-op rather than a rename that
rewrites nine fields to the same value plus a space. Both answers are
defensible; this one is chosen. A case-only change ("Me" → "me") IS treated
as a real rename, which is correct — the user asked for it — though note it
leaves `HouseholdIdentity.isPlaceholder` still true, since that test is
case-insensitive.

## Pending, not yet resolved

An agent reported that two claims made around PersonProfileView's 2×2
count wrap are false at AX3/AX5 — "dividers still separate columns" and
"default size unchanged". The wrap itself verified correct. Detail hadn't
landed when the branch froze; check this before trusting either statement
in the code or in the spec.
