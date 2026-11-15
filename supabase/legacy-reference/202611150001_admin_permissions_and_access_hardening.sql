-- CRYSTAL INVESTMENTS: granular Junior Admin permissions and read-policy hardening.
-- Forward-only: does not delete, rewrite, reset or migrate any investor/financial records.
-- Apply only after confirming migrations 202611110003, 202611120004,
-- 202611120005 and 202611130006 are present in the target project's history.

DO $$
BEGIN
  IF to_regclass('public.crystal_admin_memberships') IS NULL
     OR to_regclass('public.crystal_admin_audit_log') IS NULL
     OR to_regprocedure('public.crystal_admin_has_permission(text)') IS NULL
     OR to_regclass('public.deposit_requests') IS NULL
     OR to_regclass('public.withdrawal_requests') IS NULL
     OR to_regclass('public.investor_profiles') IS NULL
     OR to_regclass('public.investor_ledger_entries') IS NULL
     OR to_regclass('public.crystal_site_configuration') IS NULL
     OR to_regclass('public.crystal_admin_conversations') IS NULL
     OR to_regclass('public.crystal_support_messages') IS NULL
     OR to_regclass('public.investment_allocations') IS NULL
     OR to_regclass('public.investment_distributions') IS NULL
     OR to_regclass('public.investor_documents') IS NULL
     OR to_regclass('public.platform_settings') IS NULL
     OR to_regprocedure('public.admin_clear_resolved_support_messages()') IS NULL THEN
    RAISE EXCEPTION 'CRYSTAL admin prerequisites are missing. Inspect migration history and live schema before applying this migration.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.admin_update_junior_permissions(
  p_user_id uuid,
  p_permissions jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_previous jsonb;
  v_key text;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.crystal_admin_memberships m
    WHERE m.user_id = (SELECT auth.uid())
      AND m.role = 'Supa Admin'
      AND m.is_active = true
  ) THEN
    RAISE EXCEPTION 'Only an active Supa Admin may change Junior Admin permissions';
  END IF;
  IF COALESCE((SELECT auth.jwt()->>'aal'), 'aal1') <> 'aal2' THEN
    RAISE EXCEPTION 'Multi-factor authentication (AAL2) is required';
  END IF;
  IF p_permissions IS NULL OR jsonb_typeof(p_permissions) <> 'object' THEN
    RAISE EXCEPTION 'Permissions must be supplied as a JSON object';
  END IF;

  FOR v_key IN SELECT key FROM jsonb_object_keys(p_permissions) AS keys(key) LOOP
    IF v_key NOT IN (
      'overview', 'analytics', 'investors', 'kyc', 'deposit_approvals',
      'withdrawal_approvals', 'portfolio', 'opportunities', 'distributions',
      'referrals', 'team', 'website_content', 'platform_settings',
      'market_conditions', 'support', 'reports', 'admin_conversations',
      'system_health'
    ) THEN
      RAISE EXCEPTION 'Unsupported Junior Admin permission: %', v_key;
    END IF;
    IF jsonb_typeof(p_permissions -> v_key) <> 'boolean' THEN
      RAISE EXCEPTION 'Permission % must be true or false', v_key;
    END IF;
  END LOOP;

  SELECT m.permissions INTO v_previous
  FROM public.crystal_admin_memberships m
  WHERE m.user_id = p_user_id AND m.is_active = true AND m.role = 'Junior Admin'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active Junior Admin account not found';
  END IF;

  UPDATE public.crystal_admin_memberships
  SET permissions = p_permissions, updated_at = now()
  WHERE user_id = p_user_id AND role = 'Junior Admin' AND is_active = true;

  INSERT INTO public.crystal_admin_audit_log(actor_id, action, target_type, target_id, details)
  VALUES (
    (SELECT auth.uid()),
    'junior_admin_permissions_updated',
    'admin',
    p_user_id::text,
    jsonb_build_object('previous_permissions', COALESCE(v_previous, '{}'::jsonb), 'new_permissions', p_permissions)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_junior_permissions(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_junior_permissions(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_analytics_summary()
RETURNS TABLE(
  currency text,
  approved_deposits numeric,
  approved_withdrawals numeric,
  pending_deposits bigint,
  pending_withdrawals bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.crystal_admin_has_permission('analytics') THEN
    RAISE EXCEPTION 'Analytics permission required';
  END IF;
  RETURN QUERY
  WITH currencies AS (
    SELECT d.currency FROM public.deposit_requests d
    UNION SELECT w.currency FROM public.withdrawal_requests w
  )
  SELECT c.currency,
    COALESCE((SELECT SUM(d.amount) FROM public.deposit_requests d WHERE d.currency=c.currency AND lower(d.status)='approved'),0)::numeric,
    COALESCE((SELECT SUM(w.amount) FROM public.withdrawal_requests w WHERE w.currency=c.currency AND lower(w.status)='approved'),0)::numeric,
    (SELECT COUNT(*) FROM public.deposit_requests d WHERE d.currency=c.currency AND lower(d.status) IN ('pending','under_review'))::bigint,
    (SELECT COUNT(*) FROM public.withdrawal_requests w WHERE w.currency=c.currency AND lower(w.status) IN ('pending','under_review'))::bigint
  FROM currencies c ORDER BY c.currency;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_get_analytics_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_analytics_summary() TO authenticated;

-- Replace broad administrator read policies with the matching module permission.
-- Supa Admin continues to pass crystal_admin_has_permission() by design.
DROP POLICY IF EXISTS "Admins read all deposit requests" ON public.deposit_requests;
DROP POLICY IF EXISTS "Admins read deposit requests" ON public.deposit_requests;
CREATE POLICY "Admins with deposit permission read deposit requests"
  ON public.deposit_requests FOR SELECT TO authenticated
  USING (public.crystal_admin_has_permission('deposit_approvals'));

DROP POLICY IF EXISTS "Admins read all withdrawal requests" ON public.withdrawal_requests;
DROP POLICY IF EXISTS "Admins read withdrawal requests" ON public.withdrawal_requests;
CREATE POLICY "Admins with withdrawal permission read withdrawal requests"
  ON public.withdrawal_requests FOR SELECT TO authenticated
  USING (public.crystal_admin_has_permission('withdrawal_approvals'));

DROP POLICY IF EXISTS "Admins read all investor profiles" ON public.investor_profiles;
DROP POLICY IF EXISTS "Admins can view investor profiles" ON public.investor_profiles;
CREATE POLICY "Admins with investor permission read investor profiles"
  ON public.investor_profiles FOR SELECT TO authenticated
  USING (public.crystal_admin_has_permission('investors'));

DROP POLICY IF EXISTS "Admins read all ledger entries" ON public.investor_ledger_entries;
DROP POLICY IF EXISTS "Admins manage allocations" ON public.investment_allocations;
DROP POLICY IF EXISTS "Admins read investor allocations" ON public.investment_allocations;
CREATE POLICY "Admins with portfolio permission read allocations"
  ON public.investment_allocations FOR SELECT TO authenticated
  USING (public.crystal_admin_has_permission('portfolio'));

-- Remove legacy direct-write policies: controlled financial RPCs remain the only admin mutation path.
DROP POLICY IF EXISTS "Admins insert ledger entries" ON public.investor_ledger_entries;
DROP POLICY IF EXISTS "Admins manage distributions" ON public.investment_distributions;
DROP POLICY IF EXISTS "Admins review documents" ON public.investor_documents;
DROP POLICY IF EXISTS "Admins manage platform settings" ON public.platform_settings;
CREATE POLICY "Admins with reports permission read ledger entries"
  ON public.investor_ledger_entries FOR SELECT TO authenticated
  USING (public.crystal_admin_has_permission('reports'));

DROP POLICY IF EXISTS "admins read audit log" ON public.crystal_admin_audit_log;
DROP POLICY IF EXISTS "Admins read audit log" ON public.crystal_admin_audit_log;
CREATE POLICY "Admins with reports permission read crystal audit log"
  ON public.crystal_admin_audit_log FOR SELECT TO authenticated
  USING (public.crystal_admin_has_permission('reports'));

DROP POLICY IF EXISTS "admins read site config" ON public.crystal_site_configuration;
CREATE POLICY "Admins with site permission read site configuration"
  ON public.crystal_site_configuration FOR SELECT TO authenticated
  USING (
    (config_key = 'website_content' AND public.crystal_admin_has_permission('website_content'))
    OR (config_key = 'platform_settings' AND public.crystal_admin_has_permission('platform_settings'))
  );

DROP POLICY IF EXISTS "Only admins read admin conversations" ON public.crystal_admin_conversations;
CREATE POLICY "Admins with conversation permission read admin conversations"
  ON public.crystal_admin_conversations FOR SELECT TO authenticated
  USING (public.crystal_admin_has_permission('admin_conversations'));

-- The policies above restrict SELECT access. Financial status changes must continue
-- through the existing permission-checked, transactional review RPCs, not direct browser updates.

-- Public website configuration reader returns only explicitly approved presentation fields.
-- It never exposes arbitrary configuration JSON or administrative secrets.
CREATE OR REPLACE FUNCTION public.crystal_get_public_site_configuration()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'platform_settings', COALESCE((
      SELECT jsonb_build_object(
        'contactEmail', c.config_value -> 'contactEmail',
        'contactPhone', c.config_value -> 'contactPhone',
        'headquarters', c.config_value -> 'headquarters',
        'defaultCurrency', c.config_value -> 'defaultCurrency',
        'footerTagline', c.config_value -> 'footerTagline'
      ) FROM public.crystal_site_configuration c WHERE c.config_key='platform_settings'
    ), '{}'::jsonb),
    'website_content', COALESCE((
      SELECT jsonb_build_object(
        'homeEyebrow', c.config_value -> 'homeEyebrow',
        'homeDescription', c.config_value -> 'homeDescription',
        'aboutIntro', c.config_value -> 'aboutIntro',
        'opportunitiesIntro', c.config_value -> 'opportunitiesIntro'
      ) FROM public.crystal_site_configuration c WHERE c.config_key='website_content'
    ), '{}'::jsonb)
  );
$$;
REVOKE ALL ON FUNCTION public.crystal_get_public_site_configuration() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crystal_get_public_site_configuration() TO anon, authenticated;

-- Private administrator conversations require an explicit module permission.
CREATE OR REPLACE FUNCTION public.admin_send_conversation_message(p_message text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
  v_email text;
BEGIN
  IF NOT public.crystal_admin_has_permission('admin_conversations') THEN
    RAISE EXCEPTION 'Administrator conversations permission required';
  END IF;
  IF length(trim(COALESCE(p_message, ''))) < 1 OR length(p_message) > 5000 THEN
    RAISE EXCEPTION 'Message must be 1 to 5000 characters';
  END IF;
  SELECT u.email INTO v_email FROM auth.users u WHERE u.id = (SELECT auth.uid());
  INSERT INTO public.crystal_admin_conversations(sender_id, sender_email, message)
  VALUES ((SELECT auth.uid()), COALESCE(v_email, ''), trim(p_message)) RETURNING id INTO v_id;
  INSERT INTO public.crystal_admin_audit_log(actor_id, action, target_type, target_id)
  VALUES ((SELECT auth.uid()), 'admin_conversation_message_sent', 'admin_conversation', v_id::text);
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_send_conversation_message(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_send_conversation_message(text) TO authenticated;

-- Preserve support evidence: archive resolved messages instead of permanently deleting them.
ALTER TABLE public.crystal_support_messages
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;
REVOKE ALL ON FUNCTION public.admin_clear_resolved_support_messages() FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.admin_archive_resolved_support_message(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.crystal_admin_memberships m
    WHERE m.user_id = (SELECT auth.uid()) AND m.role = 'Supa Admin' AND m.is_active = true
  ) THEN
    RAISE EXCEPTION 'Only Supa Admin may archive support records';
  END IF;
  IF COALESCE((SELECT auth.jwt()->>'aal'), 'aal1') <> 'aal2' THEN
    RAISE EXCEPTION 'Multi-factor authentication (AAL2) is required';
  END IF;
  UPDATE public.crystal_support_messages
  SET archived_at = now(), archived_by = (SELECT auth.uid())
  WHERE id = p_message_id AND status = 'resolved' AND archived_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'Only an unarchived resolved support message can be archived'; END IF;
  INSERT INTO public.crystal_admin_audit_log(actor_id, action, target_type, target_id)
  VALUES ((SELECT auth.uid()), 'support_message_archived', 'support_message', p_message_id::text);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_archive_resolved_support_message(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_archive_resolved_support_message(uuid) TO authenticated;

-- Enforce key-specific site permissions; a content editor cannot change platform settings.
CREATE OR REPLACE FUNCTION public.admin_save_site_configuration(p_key text, p_value jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_key text;
BEGIN
  IF p_key NOT IN ('platform_settings', 'website_content') THEN
    RAISE EXCEPTION 'Invalid configuration key';
  END IF;
  IF p_key = 'platform_settings' AND NOT public.crystal_admin_has_permission('platform_settings') THEN
    RAISE EXCEPTION 'Platform settings permission required';
  END IF;
  IF p_key = 'website_content' AND NOT public.crystal_admin_has_permission('website_content') THEN
    RAISE EXCEPTION 'Website content permission required';
  END IF;
  IF p_value IS NULL OR jsonb_typeof(p_value) <> 'object' THEN
    RAISE EXCEPTION 'Configuration must be a JSON object';
  END IF;
  FOR v_key IN SELECT key FROM jsonb_object_keys(p_value) AS keys(key) LOOP
    IF (p_key = 'platform_settings' AND v_key NOT IN ('contactEmail','contactPhone','headquarters','defaultCurrency','footerTagline'))
       OR (p_key = 'website_content' AND v_key NOT IN ('homeEyebrow','homeDescription','aboutIntro','opportunitiesIntro')) THEN
      RAISE EXCEPTION 'Unsupported configuration field: %', v_key;
    END IF;
    IF jsonb_typeof(p_value -> v_key) <> 'string' THEN
      RAISE EXCEPTION 'Configuration field % must be text', v_key;
    END IF;
    IF length(p_value ->> v_key) > 5000 THEN
      RAISE EXCEPTION 'Configuration field % is too long', v_key;
    END IF;
  END LOOP;
  INSERT INTO public.crystal_site_configuration(config_key, config_value, updated_by)
  VALUES (p_key, p_value, (SELECT auth.uid()))
  ON CONFLICT (config_key) DO UPDATE
    SET config_value = EXCLUDED.config_value, updated_by = EXCLUDED.updated_by, updated_at = now();
  INSERT INTO public.crystal_admin_audit_log(actor_id, action, target_type, target_id, details)
  VALUES ((SELECT auth.uid()), 'site_configuration_saved', p_key, p_key, jsonb_build_object('fields', (SELECT coalesce(jsonb_agg(key), '[]'::jsonb) FROM jsonb_object_keys(p_value) AS keys(key))));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_save_site_configuration(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_site_configuration(text, jsonb) TO authenticated;

-- Financial mutations remain fail-closed until the live ledger anomalies have been reconciled
-- and the eight-division deposit allocation / proportional withdrawal workflow is deployed.
-- This changes function privileges only; no existing financial records are changed.
DO $$
BEGIN
  IF to_regprocedure('public.admin_review_financial_request(text,uuid,text)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.admin_review_financial_request(text,uuid,text) FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.admin_create_investment_allocation(text,text,numeric,text,text)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.admin_create_investment_allocation(text,text,numeric,text,text) FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.admin_update_investment_allocation(uuid,text)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.admin_update_investment_allocation(uuid,text) FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.investor_submit_withdrawal(numeric,text,jsonb)') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.investor_submit_withdrawal(numeric,text,jsonb) FROM PUBLIC, anon, authenticated';
  END IF;
END;
$$;

-- Stop investor page reads from triggering earnings accrual. A scheduled, service-side
-- accrual process must be installed and verified before these functions are re-enabled.
DO $$
BEGIN
  IF to_regprocedure('public.investor_accrue_daily_earnings()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.investor_accrue_daily_earnings() FROM PUBLIC, anon, authenticated';
  END IF;
  IF to_regprocedure('public.investor_get_earnings_summary()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.investor_get_earnings_summary() FROM PUBLIC, anon, authenticated';
  END IF;
END;
$$;
