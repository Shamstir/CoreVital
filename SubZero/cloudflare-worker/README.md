# SubZero FCM worker

This free-tier Cloudflare Worker receives a short-lived Mac pairing request,
lets the authenticated Android app claim it, and sends thermal alerts through
Firebase Cloud Messaging (FCM).

## Deploy once

1. Create a Cloudflare account and install Wrangler (`npm install`).
2. In Cloudflare, create a KV namespace named `subzero-pairings`; copy its ID
   into `wrangler.toml`.
3. In Google Cloud Console for Firebase project `subzero-4d986`, create a
   service account key that can send Firebase Cloud Messaging messages. Keep
   the JSON file private.
4. From this directory, set Worker secrets:

   ```sh
   npx wrangler secret put FIREBASE_PROJECT_ID
   # enter: subzero-4d986
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_JSON
   # paste the complete service-account JSON on one line
   npx wrangler deploy
   ```

5. Copy the deployed `https://...workers.dev` URL.
6. Set that URL in the Mac target's `SUBZERO_PAIRING_WORKER_URL` value in
   `Info.plist`.
7. Build Android with the same URL:

   ```sh
   flutter run --dart-define=SUBZERO_PAIRING_WORKER_URL=https://YOUR-WORKER.workers.dev
   ```

Never put the Firebase service-account JSON in either app. It belongs only in
the Cloudflare Worker secret store.
