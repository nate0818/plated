# Plated website copy review

## Voice

Plated helps people share the work of dinner. The writing should make that
benefit easy to understand: warm, specific, and comfortable to say aloud.
Personality comes from recognizable moments, such as taking turns cooking,
not from making every sentence into a tagline.

- Lead with a useful benefit, then explain what the product does.
- Use familiar words: meal plan, recipes, groceries, household, friends.
- Use “recipe book” consistently in marketing copy. “Table” names the private
  social feature; explain it through sharing with friends.
- Keep headlines connected and omit terminal periods. Use complete sentences
  in explanatory copy; sample social posts can sound more conversational.
- Use American spelling.
- Say “request” when access requires an invitation. Do not imply immediate
  access, an available App Store release, or an effortless one-step setup.
- Keep the sample household and conversation clearly labeled as examples.

## Main changes

| Before | After | Reason |
| --- | --- | --- |
| One list for the shopping | Share a grocery list | Familiar language and a clear action |
| Everyone has the plan | Plan dinner together | Describes the collaboration |
| Every night has a cook | See who’s cooking | Describes visibility without promising every night is assigned |
| Everybody’s bringing something | You’ve got tonight / Sam’s got tomorrow | Makes taking turns concrete; avoids implying a potluck |
| The ingredients are everyone’s business | One grocery list / for everyone | Names the feature and why sharing helps |
| All the pieces in one place | Less back-and-forth / before dinner | Connects the tools to the problem they help solve |
| A good thing to pass around | Dinner ideas / from friends | Makes the social benefit clear |
| Make dinner a shared thing | Get everyone / in on dinner | More natural, direct invitation |
| Get early access | Request early access | Matches the action and approval process |
| Before you pull up a chair | A few things / to know | Removes a metaphor from practical information |
| That didn’t save. Try again. | We couldn’t send your request. Please try again. | Names the failed action and offers a next step |
| No account to make. Sign in with Apple, and that’s the whole setup. | Sign in with Apple to get started. | Removes an overstated setup promise |

## Coverage

Updated the local direction preview and existing homepage copy, recipe and
grocery sections, Table examples, FAQs, early-access page and form states,
invitation pages, missing-page messages, metadata, image descriptions, and
App Store availability text. Privacy-policy prose and native app screenshots
were left to their existing owners; product claims were kept within the
features already represented in the app and website.

The visual design, interactions, and access-request handling remain the same.
These edits are prepared locally; this review does not publish a deployment.

## Validation

- Production build, TypeScript, and targeted ESLint checks passed.
- Preview checked at 320, 390, 430, 760, 803, 815, 1024, and 1280 CSS pixels.
  The main headlines retain two lines, with no horizontal or heading overflow.
- Viewed the early-access flow, homepage, both invitation types, and missing-page
  preview in the browser. No access requests or emails were submitted.
