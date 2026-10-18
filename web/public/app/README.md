# Current app captures

`editorial-{plan,recipes,groceries,table}-current.png` are unaltered native
simulator captures from `docs/editorial-2026-10-16/{screen}-current.png`.
They include the shared cream selection controls, darker neutral surfaces,
refined date wheel and original orange primary actions. All four use the
memory-only sample household. The homepage, screen explorer, and social-card
generator reference these current files. Earlier WebP files are historical.

`pancakes.webp` remains the existing photo from `design/photos/pancakes.jpg`.

`editorial-recipes-light-current.png` is an unaltered 1206 × 2622 capture of the
running sample household on Plated-QA-Sandbox / iOS 26.5, Plated 1.0.1 (32).
The app's own Settings → Light appearance was selected for the website hero.
The simulator was returned to Editorial appearance and Plan after capture.
The image has not been recoloured or reconstructed.

## 8:18 product story

`plan-light-818.png`, `recipes-light-818.png`, and `groceries-light-818.png`
are unaltered 1206 × 2622 captures from Plated-QA-Sandbox, iOS 26.5,
Plated 1.0.1 (32), using the memory-only demonstration household and the app’s
Light appearance. The simulator status-bar clock was temporarily set to 8:18
using Apple’s capture override, then cleared. No pixels were retouched.

`plated-preview-818.mp4` is an H.264 recording from that same app,
starting on Plan and opening Recipes. AVFoundation trims and encodes the native
recording for browser delivery. The UI is not reconstructed or recoloured.
The QA app was returned to Editorial appearance and Plan after capture.

These replace the earlier Light Recipes hero image on the homepage and social
card. Native demonstration data is for capture only and is not advertised as a
preloaded consumer cookbook.

`plan-sam-light-818.png` is an unaltered capture from that same QA simulator
and app version, with the date wheel set to Saturday October 17. It shows
Sam’s avatar, Pizza Night, and “Sam is cooking”. The Plan walkthrough and its
enlarged view now use this capture. The rejected avatar selector is removed.
Unused Riley and Household captures are retained under
`docs/website-household-preview-2026-10-16/`, outside the served website folder.
The status-bar override was cleared after capture.

`plated-collaboration-818.mp4` is a smaller 588 × 1280 H.264 encode of the same
native recording, prepared with AVFoundation for the homepage collaboration
story. Playback starts with your Plan, opens Recipes, then holds the existing
`plan-sam-light-818.png` capture to show Sam cooking tomorrow. The household
avatars reflect those captures; the phone UI is not reconstructed or edited.

## Consistent cooking preview — October 17

The hero now cycles through the three native Plan captures (You, Sam, Riley)
with a 700 ms crossfade and six seconds to read each night. It no longer
switches between the recording (which included the device island) and a still
(which did not). A permanent decorative device island belongs to the website
frame, outside the unchanged capture pixels, and is also used on the tour.
`plan-riley-light-818.png` is the previously retained, unaltered capture from
`docs/website-household-preview-2026-10-16/`.

The marketing avatar for You is a person outline, while Sam and Riley retain
their name initials. The app captures retain the actual signed-in QA profile.
Table is now a labeled, animated web illustration of sharing, commenting and
saving, based on the native demonstration household’s Pancake Dinner post and
Riley’s existing comment. It is not a recording or live user activity.

Both previews pause offscreen, in background tabs, with Reduce Motion or Save
Data, and via a visible Play/Pause button. No simulator settings or household
data were changed for this revision.
