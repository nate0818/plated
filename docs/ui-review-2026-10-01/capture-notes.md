# Plated UI review capture notes

Captured October 1, 2026 from an isolated copy of the working tree based on commit e5e065a, including the local uncommitted source changes present when the copy was made. Original screen captures are retained. Follow-up simulator QA captures were added after feedback-driven source changes and are stored in `qa-captures`; the original screens remain unchanged.

The review contains 62 app screens and states, 27 widget and timer layouts, and two share extension states. App captures use an iPhone simulator in portrait, light appearance, with the in-memory design review fixture. Screens that require iCloud show the simulator's signed-out or unavailable account state. Onboarding uses the existing review fixtures. Cooking method and timer captures use additional sample method text.

The gallery opens native view types individually. Most sheets are presented over the week view. Individual pushed destinations can omit the shell's tab bar. The launch capture holds the existing launch animation at its wordmark. The household badge view is rendered as a standalone destination.

Widget captures render their source views at representative dimensions for each supported widget family, with the built-in sample entry. Timer Lock Screen captures render the source content with sample activity state. Dynamic Island previews reproduce the source content layout without iOS system chrome. These are layout reviews, not captures of installed home screen widgets or an active system Dynamic Island.

Share extension captures render its existing UIKit layout in sending and saved states without collecting or sharing a recipe. Disabled Plated Plus and Prongsby views are included and labeled in the document.

Coverage is of primary native destinations, app-owned sheets and the selected distinct states listed in the manifests. It does not cover every conditional dialog, scroll position, empty or failure permutation, system camera and photo picker, iPad layout, dark appearance, or accessibility text size. Long pages show a viewport rather than a stitched full scroll view.

Each document page has an A, W or X screen ID and an editable feedback area. Original screenshot files are retained in `screens` and `widgets`; manifests list their source route IDs and filenames.


## Follow-up QA captures

The all-screen ZIP and overview prefer a fresh QA capture when one exists; otherwise they retain the original source image. This keeps the full 91-image review bundle intact while showing the latest implementation for changed app screens.

On October 8, 2026, the signed iPhone 17 Pro / iOS 26.5 simulator build was relaunched against the in-memory review fixture. Fresh targeted simulator captures cover A01 week plan, A05 move meal, A14 recipe picker, A15 recipe share, A18 Table composer, A20 thread, A28 profile edit and banner crop, A30 household member invite, A34 gathering, A37 sign-in calendar motif, A38 profile setup, A44 launch opener, A50 question composer, A54 navigation cleanup, A56 cooking timer controls, A59 recipe ingredients, A61 embedded Groceries spacing and A62 populated activity. These are viewport captures, not exhaustive state coverage. The A28 crop still needs direct drag/pinch gesture verification. Widget behavior changes W01–W04 and W09–W11 still need a fresh installed-widget family visual pass.
