# Open decisions

Things found, measured, and deliberately **not** decided, because each one is
a judgment call with two defensible answers and a visible cost either way.
They are here rather than in a commit message so the next person to open the
question starts from the measurement instead of the argument.

Everything in this file has been verified against the code as it stands. If a
line names a file, check it still says what this says before acting on it.

---

## 1. Avatar initials fail contrast, and the owner does not

`AvatarCircle` paints the initials in the person's `tone` on that person's
`tint`. Measured on canvas in the light room:

| pair | ratio |
|---|---|
| tomato on `tomatoTint` | 2.73:1 |
| basil on `basilTint` | 2.87:1 |
| amber on `mangoTint` | 2.98:1 |
| **neutral (the owner)** on `fill` | **15.09:1** |

The floor for a glyph this size is 3.0:1, so all three colour pairs miss it,
and becoming a coloured member measurably makes your own name harder to read
than the owner's.

**The two answers pull opposite ways.** Ink letters on the existing pale tint
gives 15:1 and stays inside DESIGN.md's quiet register, but the person's
colour nearly disappears at 22pt. White letters on a *saturated* disc gives
3.10–3.56:1, keeps identity legible across the app, and is what Messages and
Contacts do — but a grid of saturated discs is louder than "quiet chrome,
earned colour" describes.

Either changes every avatar in the app. Not a 4am call.

## 2. `symbolMatching` and `gabaritoMatching` have zero call sites

`BrandFonts.swift` defines both, with worked cap-height ratios and a comment
saying "every glyph-next-to-text pair in the app was off by roughly 6%". Grep
returns no callers anywhere.

Meanwhile every SF Symbol in the app is `.font(.system(size:))`, which is
frozen: it does not scale with Dynamic Type at all. Inside `.plChrome()` that
is correct — chrome caps its type on purpose. In content it is not.

Adopting the helpers wholesale resizes icons on every screen at once, which
needs a device pass at several type sizes before anyone can say it looks
right. Until then the two functions are a solution sitting next to its
problem, which is worse than not having them, because a future session will
read them and assume the app is cap-matched.

## 3. "Saved by others" cannot count what it says

`Awards.recordSaveReceived(by:)` is called **on this device** when *you* save
somebody's post, keyed by that post's author. So the ledger records "on this
phone, I saved N dishes by <author>".

`HouseholdStatsView` then sums `savesReceived(by:)` across household members
and labels it "Saved by others". It cannot ever count a save another
household made — that happens on their device and nothing carries it here.
On your own profile the number is structurally zero.

Relabelling it to what it counts ("dishes you saved") makes it honest but
turns a social signal into a personal one. Removing it is a product decision.
Leaving it is the only option that is definitely wrong.

## 4. `safeAreaBar` and the scroll edge effect

No scroll view in the app registers a scroll edge effect, so content runs out
from beside and under the floating tab bar instead of dissolving into it.
`safeAreaBar(edge:)` is the iOS 26 answer and is callable from an 18.0 target
behind `#available`.

The reason it is not done: eleven scroll views hand-pad with
`Layout.floatingChromeInset`, which this branch just changed to follow
`ProngsbyFeature`. Adopting `safeAreaBar` makes the OS apply that inset
itself, so the two would double up until every call site is unwound
together. It is a single coherent change across a dozen files, and it wants
someone watching the screen while it lands.

## 5. The layered app icon

`AppIcon.appiconset` holds three flat PNGs (default, dark, tinted) and no
`.icon` document. On iOS 26 that means no layered lighting and no artwork at
all for the Clear appearance.

The mark is already two layers by construction — persimmon ground, white
wordmark with its dot — so this is a rebuild in Icon Composer rather than a
redesign, and DESIGN.md's ban on inventing a logo badge is not in the way.
It cannot be authored headlessly.

## 6. The landscape month is unverified

`MonthPlannerView` renders when `verticalSizeClass == .compact`. It has a
`-plated-force-month` test hook, but that hook draws the landscape layout at
portrait width, where the seven-column grid overflows both edges — an
artifact of the hook, not a real state.

The 2026 audit claims the month does not fit on screen in real landscape.
Arithmetic supports the concern (six rows of 64pt plus a header and the tab
bar exceed 402pt of landscape height), and the grid *is* inside a
`ScrollView`, so the likely truth is "you must scroll to reach the end of the
month" rather than "content is lost". **Nobody has looked at it on a rotated
device.** Do that before designing a fix.

## 7. TextField placeholders use the system tint

Every `TextField` in the app relies on iOS's default `placeholderText`, which
is very light. DESIGN.md names placeholders explicitly among the things that
must not be painted in a tone too faint to read.

This is the platform default that Apple itself ships, and overriding it
touches every text field in the app. Worth a deliberate decision rather than
a drive-by.

## 8. The plate count is painted tomato

`TableFeedView` paints the plate count `tomato` when you are among the
platers: 3.10:1 on canvas, at `.body` bold (15pt), which clears the 3.0:1
floor for large text. So it passes — but the *glyph* beside it already fills
tomato, so the colour is carrying the same fact twice, and Instagram
deliberately paints the count in its label colour and reserves red for the
heart.

Fifteen other `Text` sites paint tomato legitimately (today markers, which
DESIGN.md explicitly permits, and action labels), so there is no blanket rule
to apply here. Marginal, passing, and a matter of taste.

## 9. Sign in with Apple fails silently

`SignInView` opens the door on any non-cancel failure, saves no identity, and
never mentions it. The comment argues the case — planning must not be hostage
to an Apple outage — and that reasoning holds.

The gap is only that the person is never told they are running without an
identity, and features that depend on one will quietly do nothing. Where to
say so, and how loudly, is a design question about a screen somebody has
already left.
