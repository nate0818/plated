# Slice A — Multi-phone household rehearsal

**Status:** Ready when Nate says go  
**Purpose:** Measure the household / Table pipes that only exist between real iCloud accounts. This is a rehearsal, not a feature. A green `make test` is not a pass.

**Build:** TestFlight or `make phone` from `main` (includes C fail-open + B-hide + Account path).  
**Phones:** Two unlocked iPhones minimum; three Apple IDs if testing Remove while someone else stays in. **Not** Simulator. Notifications allowed. Do not force-quit the invitee during the background-banner step.

Write pass/fail into `docs/notifications.md` (silent push) and `docs/open-decisions.md` §17 (Remove).

---

## Setup (step 0)

| Check | Pass |
|---|---|
| Two/three **unlocked** iPhones, TestFlight (or Debug) build, iCloud on | — |
| Notifications allowed | — |
| Host: Settings → Household and Table activity **On** | — |
| Not Simulator / not force-quit on invitee for step 6 | — |

---

## Script

| # | Action | Pass | Fail (write down) | Console to watch |
|---|---|---|---|---|
| 1 | Host: Home → Add someone → **Invite someone** → send the text | Composer sends. Host row: **Invited** | Pill missing (`canSendText` false). Row never appears (cancelled composer is correct) | `PLATED INVITE: composer finished, result = 0` (sent) |
| 2 | Invitee: tap plated.food link → **Join** (not Copy) | Join sheet names the host. After Join: Plan tab, host’s nights visible. Host row becomes **Joined** without needing “They're in.” | “Couldn't reach iCloud” + empty week. Host stuck on Invited | `PLATED HOUSEHOLD: joining…` then pull, not `first pull brought nothing` |
| 3 | Host: plan **Thursday** with ingredients. Invitee: open Plan (or wait ~1 min / pull) | Invitee sees Thursday beside their own week, **one** dinner, not two | Empty; or double night; or only after reinstall | `[Push] silent push…` **or** pull on foreground |
| 4 | Invitee: Groceries | Host’s Thursday ingredients are on the list | List ignores host night; or still shows invitee’s pre-join list | — |
| 5 | Host: swipe member → **Remove** | Riley loses plan/grocery/cookbook. Host roster gone. Riley sees household is no longer on this phone | “Couldn't remove…” **or** host row gone but Riley still reads the week | `PLATED HOUSEHOLD: removed participant` vs `could not remove participant` |
| 6 | Re-invite or use a **third** phone still in the household. Invitee **backgrounds** Plated (home screen, not swipe-up quit). Host plates a dish **or** plans Friday | Banner **or** at least `[Push] silent push from plated-…` in invitee console. Bell updates on next open either way | Silence + no `[Push]` line | `[Push] silent push from plated-shared-v1` / `plated-private-v1` |

---

## If a step fails

| Step | Do |
|---|---|
| 2 fails with empty week | Likely join commits membership before first pull succeeds. Do **not** “fix” mid-rehearsal by tapping They're in. File for a later join-rollback slice. |
| 5 fails | Leave `open-decisions.md` §17 open. Do **not** set `publicPermission = .none` (that evicts everyone). Product may honestly say Remove couldn't. |
| 6 has no `[Push]` | Stop claiming background news for this TestFlight. Copy: you'll see it when you open Plated. Bell/digest on open still counts as catch-up. |

---

## Seat honesty (already on main)

- **Invited** only after the invite actually sent
- **They're in** / Joined only after accept is verified
- Unknown = spinner, no words, no fake badge
- Never leave Invited up once they're in (Alessandra-class)

---

## Out of scope for this rehearsal

Discover, share extension, B-finish (in-app nudge / APNs), Plated+, cook-reminder rebuild, Account redesign (already on main).
