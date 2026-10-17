# Household avatars under the Plan copy — October 16, 2026

The Plan step keeps its full-size sticky phone on the left. A static group of
three household avatars sits directly beneath the description on the right.
Staggered spacing, soft paper colours and overlapping meal-photo badges make
the presentation playful without adding another interaction. The visible
labels connect You with salmon tonight, Sam with pizza tomorrow, and Riley with
steak on Tuesday. These assignments match the QA sample household. The initials
match the app’s demo avatars; no profile portraits or testimonials were invented.

The three-column group fits the mobile copy column and has no looping motion.
The list has an accessible example label, while decorative initials and food
photos are hidden from screen readers. The names and dinner cues remain text.
The existing Plan/Recipes/Groceries navigation and scroll-driven phone changes
are unchanged. There is no example table or avatar selector.

The phone uses an actual capture of Sam’s assigned Pizza Night, including the
native avatar and “Sam is cooking” label. The enlarged-screen dialog uses the
same capture. Native captures came from the memory-only sample household on
Plated-QA-Sandbox, iOS 26.5, Plated 1.0.1 (32), in Light appearance with a temporary
8:18 clock override. No native data or screenshot pixels were edited. Only
Sam’s capture is served; unused Household and Riley captures are retained here.
The clock override was cleared, Editorial appearance was restored and verified,
and the QA app was returned to its Plan root on Friday October 16.

Validation: production build and TypeScript passed; ESLint passed for ProductTour
and AppShowcase. Browser checks confirmed no horizontal overflow at 320px or
390px, all meal badges loaded, and the avatar group contains no controls. The
Plan dialog opens the same Sam capture and closes correctly. The desktop preview
had no warning/error console entries. The final screenshot uses the browser’s
normal 1422 × 800 viewport; temporary mobile overrides were cleared.
