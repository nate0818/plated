# Plated → Instacart

The native grocery sheet sends the remaining quantities in its current meal/date selection to `instacart-shopping-list`. The function creates an Instacart shopping-list page; the user reviews product matches, selects a retailer, and checks out in Instacart. Opening a link does not mark groceries as purchased or send a household order notification.

## Deployment status — September 4, 2026

- Supabase project: `dyvrksooelbkzkprqlhk`.
- Function `instacart-shopping-list`: deployed, active, version 1.
- Migration `instacart_shopping_links`: applied. Both tables have RLS enabled, no client grants, and service-role access.
- Anonymous request to the deployed endpoint: verified HTTP 401.
- Partner account/API key: not available during implementation. No live Instacart link or checkout has been verified.

## Finish activation

Add `INSTACART_API_KEY` in this project's **Edge Functions → Secrets**. Use an Instacart development key first; the function defaults to the development endpoint. For an approved production key, also set `INSTACART_ENV=production`. Keep the key out of the app, source control, and chat.

Sign in with Apple in Plated to establish the existing directory session. Open Groceries, choose dates/meals, and tap **Shop with Instacart**. Verify the returned list against both shared and meal-specific ingredients before enabling production use. The function uses `verify_jwt=false` because it authenticates `X-Plated-Session` against Plated's Apple-verified directory sessions; anonymous requests are refused by the handler.

The service has a per-account limit of 30 new lists per hour and a six-day cache of identical lists. Changing the selected ingredients or quantities changes the cache key. Unknown measures are preserved in the ingredient name rather than converted to invented package counts.

## Verification

`node --experimental-strip-types --test backend/instacart/handler.test.ts`

Ten tests cover authentication, missing configuration, payload limits, measurement mapping, caching, quantity changes, rate limits, partner errors, and unsafe return URLs. These use an injected partner response and do not establish that a live partner account is configured.

API references: [shopping-list pages](https://docs.instacart.com/developer_platform_api/api/products/create_shopping_list_page), [units](https://docs.instacart.com/developer_platform_api/api/units_of_measurement), [API keys](https://docs.instacart.com/developer_platform_api/get_started/api-keys).
