# Plated website redesign

The homepage now leads with actual Plated app captures and offers a four-screen
product explorer. Household coordination, the invite-only Table, food photography,
privacy, and common questions lead into early access and the launch waitlist.

The primary action uses the existing shared TestFlight URL. Apple's public page
was checked and identifies the Plated: Meal Planner beta. The App Store launch
waitlist is presented as a separate choice.

The app's current canvas, supporting text, and on-coral text tokens are mirrored
in the website. Gabarito and Plus Jakarta Sans are served from copies of the
native app's font files, avoiding Google Fonts requests during builds.

## Verification

- `npm run build` passed, including TypeScript and static page generation.
- Browser review at CSS widths of 320, 390, 800, and 1440 pixels found no
  horizontal page overflow.
- All four product selectors changed the matching description and real app
  screenshot; screenshot assets loaded successfully.
- FAQ expansion and native invalid-email validation were exercised.
- A production server was also used to verify the page and product selector.
- No valid email address was submitted to the production waitlist.
- `git diff --check -- web` passed.

`desktop.jpg`, `mobile.jpg`, and `full-page.jpg` are captures of the local
production build. No deployment was performed as part of this redesign.

Run `npm run dev` from `web` to explore the interactive implementation locally.
