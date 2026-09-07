# QR Handoff and Public Gift Page

Phase 2B uses `qrcode.react` to render a standards-compliant QR locally in the browser. It has no hosted QR service or runtime network dependency. The QR contains only the opaque public URL `{base}/g/{giftToken}`.

## Public URL configuration

Set `VITE_PUBLIC_GIFT_BASE_URL` in the ignored `.env.local` file when the customer-facing origin differs from the current browser origin. Leave the value empty in `.env.example`. For production, replace it with the final HTTPS customer domain; no source-code change is required.

## Staff and Customer flow

After `api.create_gift` returns `CREATED_GIFT` or `EXISTING_GIFT`, Staff immediately sees the QR, Bill summary, copy-link action, and next-Bill action. The public `/g/{giftToken}` page calls only `api.get_public_gift` and renders its approved campaign headline, description, terms, and safe status.

## Trusted local Wi-Fi UAT

Connect the Mac and phone to the same trusted Wi-Fi. Put the Mac LAN origin in `.env.local`, for example `VITE_PUBLIC_GIFT_BASE_URL=http://<LAN_IP>:<PORT>`, then run:

```sh
npm run dev -- --host 0.0.0.0 --port <PORT> --strictPort
```

Open `http://<LAN_IP>:<PORT>/login` on the Mac, create a development-only Gift, and scan its QR with the phone camera. Do not use public Wi-Fi, port forwarding, or an Internet tunnel. Stop the server after UAT, archive the Development-only Campaign, and retain its immutable Version, Prize, Gift, and Audit history.
