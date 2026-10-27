-- Source: production Postgres catalog (pg_get_functiondef, pg_policies, pg_trigger), extracted 2026-10-27 (after hardening).
-- Shows: tenant isolation via RLS helper functions, per-role policies, and a trigger that blocks privilege escalation.
-- Function bodies and policy expressions are verbatim; CREATE POLICY statements were rebuilt from pg_policies,
-- and the English section comments were added for this sample.

-- ---------------------------------------------------------------------------
-- Helper functions used by every policy.
-- Role and tenant come from public.users (keyed by auth.uid()), never from
-- user_metadata, which the user can edit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT role FROM users WHERE auth_id = auth.uid()
$function$;

CREATE OR REPLACE FUNCTION public.get_user_tenant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT tenant_id FROM users WHERE auth_id = auth.uid()
$function$;

-- ---------------------------------------------------------------------------
-- RLS is enabled on every business table.
-- ---------------------------------------------------------------------------
ALTER TABLE public.tenants            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.atendimentos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disparos           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pendencias         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.erros              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.templates_mensagem ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_channels    ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Operational tables: superadmin sees all, everyone else only their tenant.
-- No DELETE policy on these tables: deletes are denied by default.
-- ---------------------------------------------------------------------------
CREATE POLICY atendimentos_select ON public.atendimentos FOR SELECT
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY atendimentos_insert ON public.atendimentos FOR INSERT
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY atendimentos_update ON public.atendimentos FOR UPDATE
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()))
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));

CREATE POLICY clientes_select ON public.clientes FOR SELECT
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY clientes_insert ON public.clientes FOR INSERT
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY clientes_update ON public.clientes FOR UPDATE
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()))
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));

CREATE POLICY disparos_select ON public.disparos FOR SELECT
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY disparos_insert ON public.disparos FOR INSERT
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY disparos_update ON public.disparos FOR UPDATE
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()))
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));

CREATE POLICY pendencias_select ON public.pendencias FOR SELECT
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY pendencias_insert ON public.pendencias FOR INSERT
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY pendencias_update ON public.pendencias FOR UPDATE
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()))
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));

CREATE POLICY templates_select ON public.templates_mensagem FOR SELECT
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));

-- Errors: a tenant can read its own; only the agency can mark them resolved.
CREATE POLICY erros_select ON public.erros FOR SELECT
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY erros_update ON public.erros FOR UPDATE
  USING (get_user_role() = 'superadmin'::text)
  WITH CHECK (get_user_role() = 'superadmin'::text);

-- ---------------------------------------------------------------------------
-- Tenant and channel configuration: readable by the tenant, writable only by
-- the agency.
-- ---------------------------------------------------------------------------
CREATE POLICY tenants_select ON public.tenants FOR SELECT
  USING ((get_user_role() = 'superadmin'::text) OR (id = get_user_tenant_id()));
CREATE POLICY tenants_insert ON public.tenants FOR INSERT
  WITH CHECK (get_user_role() = 'superadmin'::text);
CREATE POLICY tenants_update ON public.tenants FOR UPDATE
  USING (get_user_role() = 'superadmin'::text)
  WITH CHECK (get_user_role() = 'superadmin'::text);

CREATE POLICY tenant_channels_select ON public.tenant_channels FOR SELECT
  USING ((get_user_role() = 'superadmin'::text) OR (tenant_id = get_user_tenant_id()));
CREATE POLICY tenant_channels_insert ON public.tenant_channels FOR INSERT
  WITH CHECK (get_user_role() = 'superadmin'::text);
CREATE POLICY tenant_channels_update ON public.tenant_channels FOR UPDATE
  USING (get_user_role() = 'superadmin'::text)
  WITH CHECK (get_user_role() = 'superadmin'::text);
CREATE POLICY tenant_channels_delete ON public.tenant_channels FOR DELETE
  USING (get_user_role() = 'superadmin'::text);

-- ---------------------------------------------------------------------------
-- Users: a manager (gestor) can create and edit operators of their own
-- tenant, and nothing else. Anyone can read and edit their own row.
-- ---------------------------------------------------------------------------
CREATE POLICY users_select ON public.users FOR SELECT
  USING ((get_user_role() = 'superadmin'::text)
      OR ((get_user_role() = 'gestor'::text) AND (tenant_id = get_user_tenant_id()))
      OR (auth_id = auth.uid()));
CREATE POLICY users_insert ON public.users FOR INSERT
  WITH CHECK (get_user_role() = 'superadmin'::text);
CREATE POLICY users_insert_gestor ON public.users FOR INSERT
  WITH CHECK ((get_user_role() = 'gestor'::text) AND (tenant_id = get_user_tenant_id()) AND (role = 'operador'::text));
CREATE POLICY users_update ON public.users FOR UPDATE
  USING ((get_user_role() = 'superadmin'::text) OR (auth_id = auth.uid()))
  WITH CHECK ((get_user_role() = 'superadmin'::text) OR (auth_id = auth.uid()));
CREATE POLICY users_update_gestor ON public.users FOR UPDATE
  USING ((get_user_role() = 'gestor'::text) AND (tenant_id = get_user_tenant_id()) AND (role = 'operador'::text))
  WITH CHECK ((get_user_role() = 'gestor'::text) AND (tenant_id = get_user_tenant_id()) AND (role = 'operador'::text));

-- ---------------------------------------------------------------------------
-- users_update lets a user edit their own row. This trigger closes the hole
-- that opens: nobody but the superadmin may change role, tenant or login link.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.users_sem_escalonamento()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or get_user_role() = 'superadmin' then
    return new;
  end if;

  if new.role      is distinct from old.role
  or new.tenant_id is distinct from old.tenant_id
  or new.auth_id   is distinct from old.auth_id then
    raise exception 'Mudar papel, tenant ou vinculo de login exige superadmin'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

CREATE TRIGGER users_sem_escalonamento BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION users_sem_escalonamento();
