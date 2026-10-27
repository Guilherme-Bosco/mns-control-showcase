-- Source: production Postgres catalog (pg_get_functiondef, pg_get_triggerdef), extracted 2026-10-27 (after hardening). Body is verbatim.
-- Shows: derived client state (lead/client status, totals) recalculated in the database on every service status change,
-- so the dashboard, the AI agent (n8n) and manual edits all end in the same state.

CREATE OR REPLACE FUNCTION public.atualizar_status_cliente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cliente_id uuid;
  v_total_concluidos integer;
  v_total_agendados integer;
  v_valor_total numeric;
  v_ultimo_servico text;
  v_ultimo_atendimento timestamptz;
  v_dias_desde_ultimo integer;
BEGIN
  -- Pega o cliente_id do atendimento alterado
  v_cliente_id := COALESCE(NEW.cliente_id, OLD.cliente_id);

  -- Conta atendimentos concluídos
  SELECT COUNT(*), COALESCE(SUM(valor), 0)
  INTO v_total_concluidos, v_valor_total
  FROM atendimentos
  WHERE cliente_id = v_cliente_id AND status = 'concluido';

  -- Conta atendimentos agendados
  SELECT COUNT(*)
  INTO v_total_agendados
  FROM atendimentos
  WHERE cliente_id = v_cliente_id AND status = 'agendado';

  -- Último atendimento concluído
  SELECT servico, atualizado_em
  INTO v_ultimo_servico, v_ultimo_atendimento
  FROM atendimentos
  WHERE cliente_id = v_cliente_id AND status = 'concluido'
  ORDER BY atualizado_em DESC LIMIT 1;

  -- Dias desde último atendimento
  v_dias_desde_ultimo := EXTRACT(DAY FROM NOW() - COALESCE(v_ultimo_atendimento, NOW()));

  -- Atualiza campos do cliente
  UPDATE clientes SET
    total_atendimentos = v_total_concluidos,
    valor_total_gasto = v_valor_total,
    ultimo_servico = v_ultimo_servico,
    ultimo_atendimento_em = v_ultimo_atendimento,
    -- Se tem agendamento ou conclusão → convertido
    status_lead = CASE
      WHEN (v_total_concluidos > 0 OR v_total_agendados > 0) THEN 'convertido'
      ELSE status_lead -- mantém o status atual do lead
    END,
    -- Status cliente baseado em regras
    status_cliente = CASE
      WHEN (v_total_concluidos >= 3) THEN 'vip'
      WHEN (v_total_concluidos > 0 OR v_total_agendados > 0) AND v_dias_desde_ultimo <= 90 THEN 'ativo'
      WHEN (v_total_concluidos > 0) AND v_dias_desde_ultimo > 90 THEN 'inativo'
      ELSE NULL
    END
  WHERE id = v_cliente_id;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_atualizar_status_cliente
  AFTER INSERT OR UPDATE OF status ON public.atendimentos
  FOR EACH ROW EXECUTE FUNCTION atualizar_status_cliente();
