# Implemented first arrival

October 16, 2026. Option B is now the app icon: the custom P with an open,
curved bowl, supplied in default, dark and tinted asset-catalog variants.
The generated welcome photograph shows an ordinary shared weeknight dinner.
See [asset prompts](asset-prompts.md) for exact generation instructions.

## Shipped code behavior

- Launch follows readiness on the canvas, without the wordmark/tagline interstitial.
- Welcome offers Apple sign-in or local use, with the shorter product promise.
- New users enter the actual Recipes empty state. Existing completed households
  retain their Plan destination. Neither profile photos, contacts nor the tour
  gates entry. The tour remains available from Settings.
- A household invitation received during welcome retains its destination.
  The empty state also accepts a pasted invitation, validates it, and opens the
  existing confirmation after dismissing link entry. Joining asks for a name
  only if neither the stored profile nor local owner supplies one.
- Import opens with a link field; pasted text, camera scanning, library photos
  and manual entry remain available. Parsed recipes still require review.
- Imported and manually entered recipes open their actual saved detail, with
  planning and groceries available immediately. Save failure retains the draft,
  does not navigate, and retries reuse the pending model instead of duplicating it.
- The import header scrolls with its choices at large type sizes. The welcome
  photo has explicit crop bounds; the content column is capped and centered on iPad.

## Verification

- App and widget simulator builds pass, including the final iPad layout adjustment.
- `make design tokens` passes. `git diff --check` passes.
- 403 existing unit tests pass; four additional routing tests pass.
- Four end-to-end UI tests pass on iPhone 17 Pro / iOS 26.5.
- The same four tests pass on iPhone SE (3rd generation) / iOS 26.5, including
  welcome control bounds and AX5 scrolling.
- UI tests exercise local welcome, cancel, invalid invitation, manual recipe
  save, pasted-text parsing and review, saved detail, groceries, and planning.
- Visual inspection covers typical/compact phones, AX5, Light appearance, and iPad.
- All three app icons are opaque 1024 × 1024 PNGs; default and dark are identical.

Physical-device Apple authentication, successful CloudKit invitation acceptance,
camera scanning, VoiceOver traversal, and system tinted/Clear icon rendering
remain unverified. There is no layered Icon Composer document. Save-failure
recovery is guarded in code but was not fault-injected on a device.

No TestFlight upload or physical-device installation was performed. Website
changes already in the shared working tree were not part of this implementation.

## Screenshots

- [Welcome, phone](welcome-phone.png)
- [Welcome, compact phone](welcome-compact.png)
- [Welcome, iPad](welcome-ipad.png)
- [Welcome, Light](welcome-light.png)
- [Recipes empty state](recipes-empty-phone.png)
- [Add recipe](add-recipe-phone.png)
- [Saved recipe](saved-recipe-phone.png)
- [Recipes at AX5](recipes-ax5.png)
- [Import choices at AX5, scrolled](add-recipe-ax5.png)

The saved-recipe screenshot uses a locally typed UI-test recipe without a photo.
