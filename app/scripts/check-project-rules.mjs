import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const activeRoots = ['app', 'components', 'lib'];
const sourceFiles = [];
function walk(dir) {
  for (const entry of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
    const relative = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(relative);
    else if (/\.(tsx?|jsx?)$/.test(entry.name)) sourceFiles.push(relative);
  }
}
activeRoots.forEach(walk);
const source = sourceFiles.map(file => fs.readFileSync(path.join(root, file), 'utf8')).join('\n');
const migrationPath = 'supabase/migrations/202611240001_live_security_and_processing_controls.sql';
const migration = fs.readFileSync(path.join(root, migrationPath), 'utf8');
const gitignore = fs.readFileSync(path.join(root, '.gitignore'), 'utf8');
const middleware = fs.readFileSync(path.join(root, 'middleware.ts'), 'utf8');
const nextConfig = fs.readFileSync(path.join(root, 'next.config.ts'), 'utf8');
const securityGuide = fs.readFileSync(path.join(root, 'SECURITY-AND-SETUP.md'), 'utf8');
const checks = [
  ['No browser-local financial/account storage', !/\b(localStorage|sessionStorage)\b/.test(source)],
  ['No USD/GBP currency selector in active UI', !/<option(?:\s+value=["'](?:USD|GBP)["'])?\s*>(?:USD|GBP)<\/option>/.test(source)],
  ['KES-only transaction RPC', /p_currency<>'KES'/.test(migration)],
  ['Legacy admin wrappers use crystal_admin_memberships', /create or replace function public\.crystal_is_admin\(\)[\s\S]*?from public\.crystal_admin_memberships/.test(migration)],
  ['Direct authenticated distribution writes are revoked', /revoke insert, update, delete, truncate[^;]*investment_distributions from anon, authenticated/i.test(migration)],
  ['Referral commissions limited to interest earnings', /new\.earning_type='interest'/.test(migration)],
  ['Manual verification is enforced', /check\(manual_enabled = true\)/.test(migration)],
  ['Rate changes use immediate server timestamp', /v_effective_at timestamptz:=clock_timestamp\(\)/.test(migration)],
  ['Daily accrual splits rate segments', /rate_components jsonb/.test(migration) && /lead\(b\.start_at\)/.test(migration)],
  ['M-Pesa server functions included', fs.existsSync(path.join(root, 'supabase/functions/mpesa-stk-push/index.ts')) && fs.existsSync(path.join(root, 'supabase/functions/mpesa-callback/index.ts'))],
  ['Service-role daily accrual endpoint included', fs.existsSync(path.join(root, 'supabase/functions/crystal-daily-accrual/index.ts'))],
  ['M-Pesa manual-reference fallback is available', source.includes('M-Pesa manual reference') && migration.includes('M-Pesa manual reference')],
  ['Public site is unpublished by default', fs.existsSync(path.join(root, 'middleware.ts')) && fs.readFileSync(path.join(root, 'middleware.ts'), 'utf8').includes('CRYSTAL_SITE_PUBLISHED')],
  ['Clear-view actions are present without browser storage', source.includes('Clear view') && !/\b(localStorage|sessionStorage)\b/.test(source)],
  ['No service-role key in browser client', !/NEXT_PUBLIC_[A-Z0-9_]*SERVICE_ROLE/i.test(fs.readFileSync(path.join(root, 'lib/supabase.ts'), 'utf8'))],
  ['.env files are ignored by Git', /(^|\n)\.env\*?(\n|$)/.test(gitignore) && /!\.env\.example/.test(gitignore)],
  ['Environment example contains no real secret values', !/^(?:SUPABASE_SERVICE_ROLE_KEY|SUPABASE_DB_PASSWORD|MPESA_CONSUMER_SECRET|MPESA_PASSKEY|MPESA_CALLBACK_SECRET|SMTP_API_KEY)=\S+/m.test(fs.readFileSync(path.join(root, '.env.example'), 'utf8'))],
  ['Production HTTP redirects to HTTPS', /request\.nextUrl\.protocol === \"http:\"/.test(middleware) && /secureUrl\.protocol = \"https:\"/.test(middleware)],
  ['HSTS and security response headers are configured', /Strict-Transport-Security/.test(middleware) && /X-Content-Type-Options/.test(nextConfig) && /X-Frame-Options/.test(nextConfig)],
  ['Security guide covers RLS/IDOR, Supabase Auth/MFA, validation, Cloudflare WAF and rate limits', ['IDOR','RLS','Supabase Auth','TOTP MFA','parameterized','Cloudflare','rate-limit'].every(term => securityGuide.includes(term))],
  ['KYC bucket is private', /values\('investor-documents','investor-documents',false/.test(migration)],
  ['Branch/team deactivation is soft', migration.includes("set status='Inactive'") && !source.includes('admin_delete_branch')],
  ['Site configuration is read through RPC', !source.includes('from("crystal_site_configuration")')],
  ['Eight agreed divisions are seeded', ['Energy & Petroleum','Agriculture & Agribusiness','Real Estate & Infrastructure','Mining & Minerals','Shipping & Logistics','Technology & Innovation','Global Markets & Securities','General Investments & Acquisitions'].every(name => migration.includes(`'${name}'`))],
  ['Distribution payout requires confirmation evidence', /p_provider_reference[\s\S]*p_confirmation_note/.test(migration) && /payment_confirmation_source/.test(migration)],
  ['Deposit and withdrawal submissions are idempotent', migration.includes('deposit_requests_investor_client_request_uidx') && migration.includes('withdrawal_requests_investor_client_request_uidx')],
  ['Opportunity activation requires reviewed terms and risk disclosure', migration.includes('Complete and approve the opportunity terms and transaction-specific risk disclosure before activation')],
  ['Financial analytics use posted ledger totals and flag unposted approvals', migration.includes("l.source_type='Deposit' and l.entry_type='Credit'") && migration.includes('approved_unposted_deposit_count') && migration.includes('approved_unposted_withdrawal_count')],
];
let failed = 0;
for (const [label, ok] of checks) {
  process.stdout.write(`${ok ? 'PASS' : 'FAIL'}  ${label}\n`);
  if (!ok) failed++;
}
process.stdout.write(`\n${checks.length - failed}/${checks.length} project-rule checks passed.\n`);
process.exitCode = failed ? 1 : 0;
