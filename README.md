# Vastram v0.7 — authenticated role-complete MVP

This build fixes the biggest pre-hosting problems: real Supabase Auth, role-based routing, database-side authorization, secure delivery-agent ownership, shop creation, and removal of direct order-table access from browser clients.

## Zero-cost-first architecture
- Vite + React frontend
- Supabase Free for Auth/Postgres/Realtime-ready backend
- No paid API keys required for the core workflow
- Cloudflare Pages can host the static frontend for free within its current limits

## Run locally
1. Install Node.js.
2. Copy `.env.example` to `.env.local`.
3. Put your Supabase project URL and publishable/anon key in `.env.local`.
4. In Supabase SQL Editor, run `supabase_schema.sql` in a fresh development project.
5. Create accounts from the Vastram sign-up page. New accounts start as `customer`.
6. In SQL Editor, edit `bootstrap_roles.sql` with your test account emails and run it to promote one account to admin, merchant, and agent.
7. Start:
   `npm.cmd install`
   `npm.cmd run dev -- --host 0.0.0.0`

## Important security model
- The browser never gets a service-role/secret key.
- The browser uses the Supabase publishable/anon key with Auth + RLS.
- Orders are not directly readable through the Data API. Role-specific RPCs enforce access in Postgres.
- Admin/merchant/agent access is determined by the authenticated profile role, not a client-side role selector.
- Delivery actions require the authenticated agent's user ID and active delivery session.
- The handover OTP is hashed for verification and only exposed to the customer through the customer tracking token RPC.

## Current MVP limitations
- ETA is distance + traffic-factor estimation, not live traffic.
- Customer tracking currently uses the order's customer token; production should add a customer account/order lookup UX.
- Payment is not implemented.
- Real SMS/email OTP delivery is not implemented.
- Aadhaar onboarding is intentionally not enabled until the legal/security workflow is finalized.


## v0.8 authentication
- Email/password customer signup and login
- Sign in with Google via Supabase Auth
- Password reset flow
- Roles are never selected during login; merchant/agent/admin roles are granted server-side
- Production redirect URLs must be configured explicitly in Supabase Authentication > URL Configuration
- Never expose a Supabase service-role key in Vite/frontend code

## Google OAuth setup
1. In Supabase: Authentication -> Providers -> Google, enable Google.
2. Create a Google OAuth Web client.
3. Add your local app origin (for example http://localhost:5173) to Authorized JavaScript origins.
4. Add the Supabase callback URI shown by Supabase to Authorized redirect URIs.
5. Put the Google Client ID and Client Secret into Supabase's Google provider settings.
6. Add your exact local and production app URLs under Supabase Authentication -> URL Configuration.

The Vastram frontend only needs VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY. Do not put GOOGLE_CLIENT_SECRET in .env.local or the browser bundle.
