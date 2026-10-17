# Mobile refinement and early-access requests

Marketing CTAs now lead to `/early-access`, a one-field request form. Its copy
explains batch invitations, iPhone/iPad support and the TestFlight installation
step. Saving an email confirms a request; it does not grant access or send an
invitation. Existing household and Table invitation installation links remain
functional.

Requests are stored by the existing Supabase `waitlist` function with source
`plated.food/early-access`. Launch-only signups retain `plated.food`. A launch
subscriber who explicitly requests beta access upgrades their existing row,
including when the casing differs. The literal email lookup escapes SQL pattern
characters so one address cannot upgrade another.

The founder console keeps its normal list masked, displays request purpose,
and offers founder-only, audited downloads of 100 access requests at a time,
oldest first. Fresh TOTP is checked in both the Next.js BFF and Edge Function.
The download excludes launch-only signups. Review the addresses and add selected
people to an external TestFlight group in App Store Connect. Sending invitations
remains an explicit action there. The console links Apple's current guide.

Mobile previews share a 264px frame, while the hero remains slightly larger.
Avatar meal and day labels use separate lines to avoid accidental wrapping.
The hero copy appears immediately; the phone entrance lasts 450ms, food artwork
550ms, tour fades 200ms and enlarged previews 180ms. Reduced Motion disables
decorative movement. Video pauses offscreen and in background tabs, and automatic
playback respects Data Saver when the browser exposes that preference. Hidden
desktop preview images are lazy on mobile. The optimized hero poster measured
49,852 bytes versus the original 1,262,067 bytes, a 96.0% reduction.

Verification: production build, TypeScript and scoped ESLint passed. Nine Deno
checks cover request persistence failure, explicit consent upgrades, literal
email matching, masked browsing and founder-only export limits. Four Node tests
cover the public API's purpose forwarding, failure handling and safe CSV cells.
Browser checks passed at CSS widths 320, 390, 430 and 1120px, without horizontal
overflow. They verified native form validation, 16px input text, matching mobile
frames, preview navigation, focus return, offscreen pause, desktop sticky tour
behaviour and clean warning/error logs. Returning from the request page uses a
header-aware anchor so the homepage category remains visible.

The Supabase project was INACTIVE during this pass. It was restored and reached
ACTIVE_HEALTHY before the new request handler was deployed. A temporary reserved
QA address exercised a real launch signup and subsequent early-access request;
the database held one correctly tagged row and the browser showed the honest
confirmation. That test row was removed. No real invitation or launch email was
sent. No database schema or native app code changed.
