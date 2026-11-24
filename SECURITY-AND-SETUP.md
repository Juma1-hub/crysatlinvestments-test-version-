# CRYSTAL INVESTMENTS — security and connection checklist

## Mandatory security rules

### 1. Secret management
- Never put Supabase service-role keys, database passwords, M-Pesa Daraja consumer secrets, callback secrets, SMTP credentials, signing keys or other private credentials in browser code or any `NEXT_PUBLIC_*` variable.
- Keep secrets only in the hosting provider's encrypted server-side environment-variable store (Vercel/Render) or a private backend secret store. A local `.env.local` is for local development only.
- `.env`, `.env.*` are ignored by Git; `.env.example` is the only environment file intended for source control and contains placeholders/public configuration only.
- Rotate any secret that was ever committed, pasted into a public place, or exposed in a browser bundle. Deleting the file from the latest commit is not enough.
- Browser Supabase access uses only the publishable/anon key. That key is not a secret; RLS is the security boundary.

### 2. Database authorization and IDOR protection
- Never trust a browser-supplied investor ID, admin role, permission, balance, status, amount, or ownership claim.
- Every private read/write must derive the actor from the verified Supabase Auth JWT (`auth.uid()`) and check row ownership or an active `crystal_admin_memberships` role/permission in database policies/RPCs.
- Use deny-by-default RLS on every table exposed through the Data API. Review `USING` and `WITH CHECK` clauses for SELECT/INSERT/UPDATE/DELETE separately.
- Financial/admin mutations run through narrow, audited database RPCs with explicit authorization checks. No direct client writes to ledger, earnings, allocations, payouts, role memberships, or audit records.
- Test investor A cannot read or mutate investor B's records by changing IDs; test Junior Admins cannot call Super Admin actions by bypassing the UI.

### 3. Authentication and administrator MFA
- Supabase Auth is the only authentication/password/session/recovery system. Do not implement custom password hashing, session tokens, or password reset logic.
- Require verified email, strong password policy, and TOTP MFA for all administrators. Sensitive admin RPCs must require an AAL2 JWT on the database side.
- Use Supabase's supported password reset and email verification flows. Protect recovery endpoints with CAPTCHA and provider rate limits.

### 4. Server-side validation and injection protection
- Validate every incoming value at the trusted boundary: data type, range, length, enum, currency, phone format, and allowed characters. Repeat critical validation in the database RPC; browser validation is usability only.
- Use parameterized Supabase query builders or PostgreSQL function parameters. Never concatenate user input into SQL strings or execute user-supplied SQL.
- Escape/render user-generated text safely. Do not inject untrusted content with `dangerouslySetInnerHTML`.
- Amounts, investor IDs, roles, provider status, ledger outcomes and effective timestamps are determined or rechecked server-side.

### 5. HTTPS and transport security
- Production requests over HTTP are redirected to HTTPS. Production responses set HSTS and standard browser security headers.
- Use a valid TLS certificate at the hosting provider and keep the custom domain's DNS/TLS configuration valid. Do not publish payment or login forms on an HTTP origin.

### 6. WAF, DDoS and rate limiting
- Put the production domain behind Cloudflare proxy (orange-cloud) and enable managed WAF rules, DDoS protection and bot protections.
- Configure Cloudflare rate-limit rules for `/login`, `/register`, `/forgot-password`, `/reset-password`, `/admin/login`, and sensitive `/api/*` routes. Start with a conservative per-IP threshold (for example, 5 authentication attempts per minute) and tune against legitimate traffic. Return 429 and apply a temporary challenge/block for repeated abuse.
- Also enable Supabase Auth CAPTCHA and configure the Auth rate limits in the Supabase Dashboard. Cloudflare is not a substitute for database authorization.
- Do not implement rate limiting with an in-memory process map in serverless functions; it is not shared across instances and can be bypassed by scaling/restarts. Use Cloudflare edge rules or a shared atomic rate-limit store for application endpoints.
- Keep contact-form/database RPC rate limits enabled and audited.

## Environment variables

Only browser-safe public Supabase configuration may use `NEXT_PUBLIC_`:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (or legacy anon key)

Private provider credentials, Supabase service-role key, database password, SMTP credentials and callback secrets must use server-side-only environment variable names without `NEXT_PUBLIC_`. Do not add real values to `.env.example` or source control.

## Current project implementation notes

- `.gitignore` excludes `.env` and `.env.*`, while allowing `.env.example`.
- `lib/supabase.ts` uses only the publishable/anon key in the browser; it must never accept a service-role key.
- Supabase Auth remains responsible for login and recovery. Database RLS/RPC checks remain authoritative for access.
- Middleware keeps the public site unpublished unless `CRYSTAL_SITE_PUBLISHED=true`, redirects production HTTP to HTTPS, and sets security headers.
- Database migration policies/RPCs are the authority for financial/admin permissions. Do not replace them with UI-only hiding.

## Deployment checklist (complete before public testing)

1. Add production secrets only in the hosting provider's encrypted environment settings; verify no secret is in Git history or browser bundles.
2. Enable verified email, TOTP MFA, CAPTCHA and Auth rate limits in Supabase.
3. Attach the domain to Cloudflare, enable proxy, managed WAF and DDoS protections, and configure rate limits for the routes above.
4. Confirm the hosting platform enforces valid TLS; test HTTP redirects and HSTS.
5. Run cross-account IDOR tests for investor records and role-escalation tests for Junior Admins.
6. Test validation with malformed IDs, oversized strings, invalid KES amounts, invalid Kenyan phone numbers, duplicate idempotency keys and hostile text payloads.
7. Review RLS policies, function grants, audit logs, backups and recovery procedures before enabling real-money operations.
