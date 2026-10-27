// Source: src/app/api/acao/[acao]/route.ts (Next.js route handler, in production). Sanitized: webhook path prefix, secret header name,
// and two comment sentences about the earlier version.
// Shows: the single door from the dashboard to n8n. tenant_id is overwritten from the session, never trusted from the body;
// the webhook URL and secret stay server-side. ACOES_WEBHOOK (from src/lib/webhook.ts) is a fixed allowlist of 6 actions.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { ACOES_WEBHOOK, type WebhookAction } from "@/lib/webhook";

/**
 * Ponte entre o painel e os webhooks do n8n.
 *
 * Existe por dois motivos, e o segundo é o que importa.
 *
 * **1. O segredo não pode ir para o navegador.** A tela chamava o n8n direto,
 * com a URL vindo de `NEXT_PUBLIC_N8N_WEBHOOK_URL` — e `NEXT_PUBLIC_` embute o
 * valor no bundle que o navegador baixa. Pôr um token no cliente não
 * resolveria: ele viajaria no mesmo bundle.
 * Aqui a URL e o segredo vivem em env SEM o prefixo, então nunca saem do
 * servidor.
 *
 * **2. O `tenant_id` deixa de ser palavra do cliente.** O corpo que a tela
 * manda traz `tenant_id`. Aqui ele é SOBRESCRITO pelo tenant da sessão — o que o
 * navegador mandou é descartado, não conferido. Conferir deixaria a decisão nas
 * mãos de quem pergunta; sobrescrever tira a pergunta.
 */

/** O n8n faz 3 PATCH e ainda envia WhatsApp antes de responder. */
export const maxDuration = 30;

const TIMEOUT_MS = 20_000;

export async function POST(
  req: Request,
  { params }: { params: Promise<{ acao: string }> }
) {
  const { acao } = await params;

  if (!ACOES_WEBHOOK.includes(acao as WebhookAction)) {
    return erro("Ação desconhecida", 404);
  }

  const base = process.env.N8N_WEBHOOK_URL;
  const segredo = process.env.N8N_WEBHOOK_SECRET;
  if (!base || !segredo) {
    // Falta de configuração é problema nosso, não do usuário — 500, e a
    // mensagem diz o que fazer sem vazar o que está configurado.
    return erro("Integração com o n8n não configurada no servidor", 500);
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return erro("Sessão expirada. Entre de novo.", 401);

  const { data: perfil } = await supabase
    .from("users")
    .select("tenant_id, ativo")
    .eq("auth_id", user.id)
    .maybeSingle();

  if (!perfil || perfil.ativo === false) {
    return erro("Seu acesso está desativado.", 403);
  }
  // SuperAdmin tem tenant_id nulo e não opera atendimento — sem tenant não há
  // sobre o que agir, e deixar passar cairia no n8n com tenant vazio.
  if (!perfil.tenant_id) {
    return erro("Esta ação pertence ao painel de um cliente.", 403);
  }

  const corpo = await req.json().catch(() => null);
  if (!corpo || typeof corpo !== "object" || Array.isArray(corpo)) {
    return erro("Corpo da requisição inválido", 400);
  }

  const payload = {
    ...(corpo as Record<string, unknown>),
    tenant_id: perfil.tenant_id,
  };

  try {
    // Barra no fim da env viraria `//<WEBHOOK_PATH_PREFIX>…`, que em alguns proxies é 404.
    const resposta = await fetch(`${base.replace(/\/+$/, "")}/<WEBHOOK_PATH_PREFIX>${acao}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "<WEBHOOK_SECRET_HEADER>": segredo,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    // O texto do n8n é repassado inteiro: é ele que alimenta a mensagem de erro
    // na tela e a Central de Erros. Trocar por texto genérico aqui apagaria a
    // única pista que o operador tem.
    const texto = await resposta.text().catch(() => "");

    if (!resposta.ok) {
      return erro(texto || `n8n respondeu ${resposta.status}`, 502);
    }

    return new NextResponse(texto || "{}", {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e: unknown) {
    if (e instanceof Error && e.name === "TimeoutError") {
      return erro("Timeout na comunicação com o servidor", 504);
    }
    return erro(e instanceof Error ? e.message : "Erro desconhecido", 502);
  }
}

/** Corpo de erro em texto puro — é o que `callWebhook` lê e mostra na tela. */
function erro(mensagem: string, status: number) {
  return new NextResponse(mensagem, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}
