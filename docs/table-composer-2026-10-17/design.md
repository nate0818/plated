# Table posting redesign

## Experience contract

Primary task: share a food-related moment with a chosen private Table, whether it is an ingredient, restaurant, meal, photo, recommendation, or question. Standard SwiftUI design profile, retaining Plated's editorial typography, semantic colors, spacing, and controls.

Structural alternatives considered:
1. Rename the dish form: rejected because a title-first form and large empty media placeholder still force dish-shaped content.
2. Text-first post with optional attachments and context: chosen. Writing is the primary surface; photos, titles, people, and polls are additions.
3. Meal/ingredient/restaurant wizard: rejected because categorization adds a mandatory step without improving publication or privacy.

Phone compact/regular, iPad sheet, keyboard, and Dynamic Type AX5 must retain a reachable primary action and scrollable optional fields. Draft fields belong to the composer; an atomic disk draft owns saved work; the existing persisted TablePost and publication retry own pending upload. No new CloudKit fields. Existing dish posts and recipe-derived posts retain their meaning; ordinary new posts use the existing kind string with value `post`.

States: empty, writing, photo loading/failure/removal, poll with zero/one/two-four choices, people selected, audience loading/selection, local save failure, saved draft, locally saved/pending upload. Tags alone cannot create an empty post. A failed photo must not silently publish without the selected attachment. The draft keeps text, photo, audience, tags, and pending poll choice. Repeated publication is guarded.

Motion only acknowledges optional-section and attachment changes using existing reduced-motion-aware tokens. No custom blur, parallax, or layout-dependent animation. Photo decoding occurs on selection; preview is bounded. Feed/profile text posts must show real text, not a generic plate placeholder. General posts must not claim someone cooked a dish or offer recipe conversion.

Validation and remaining limitations are recorded separately in verification.md. This work does not resolve the outstanding server-side social push delivery gap in docs/social-delivery-2026-10-17.md.
