There is no standalone `push` function on purpose. Sending lives in
`_shared/apns.ts` and is called by the function that has a reason to send
(`invite` today). An open "send anything to anyone" endpoint would need its
own auth story, and the app has no admin.
