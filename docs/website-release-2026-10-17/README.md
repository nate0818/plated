# Plated website release — October 17, 2026

Published the approved marketing redesign and a final identity correction:
the header, footer and social card use the Newsreader wordmark alone. The
approved native P mark remains the favicon and touch icon.

Commit `5fb4d69b2d00451aa66c9aeec802ba2f48d0506f` was pushed to `origin/main`.
Only website files were committed. Native app work remains outside this release.
Vercel deployment `dpl_7rgiH1UP1hdAf8WhuSRtw4vLUVnX` is READY and owns
`plated.food`. Its source matches the 139 files smoke-tested in a staged
production build, with local secrets, dependencies and Xcode output excluded.

Validation: local production build, TypeScript, scoped ESLint and diff checks
passed. The staged homepage and favicon returned 200; the app video returned
200 with video/mp4 content type. The public site shows the wordmark without a
header image, the cooking avatars, and the working TestFlight URL. The live
video reached readyState 4, with no horizontal overflow at the browser’s
751px viewport. The privacy page returns 200 and the live favicon is byte-for-byte
identical to the checked source. Browser warnings/errors and the initial
production deployment error-log query were empty. No waitlist entry was sent.

`live-wordmark.jpg` records the public result. `release.json` records the
production identity and source manifest digest. Rollback is the previous
production deployment at
https://plated-oscewussa-nate-meadows-projects.vercel.app if the homepage or
install link becomes unavailable. No rollback was needed.
