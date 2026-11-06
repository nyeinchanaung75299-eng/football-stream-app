// Lease Telegram update IDs durably across independent Edge Function instances.
export function withTelegramUpdateDedup(handler, {mode, env, fetcher = fetch}) {
  return async (req) => {
    const prefix = mode === 'viewer' ? 'TG_VIEWER' : 'TG_ADMIN';
    if (req.method !== 'POST' || !env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY ||
        !env[prefix+'_BOT_TOKEN'] || !env[prefix+'_WEBHOOK_SECRET'] ||
        req.headers.get('X-Telegram-Bot-Api-Secret-Token') !== env[prefix+'_WEBHOOK_SECRET']) {
      return handler(req);
    }
    const update = await req.clone().json().catch(() => null);
    if (!Number.isSafeInteger(update?.update_id) || update.update_id < 0) return handler(req);
    const message = update.callback_query?.message || update.message;
    const from = update.callback_query?.from || update.message?.from;
    if (!message?.chat || !from) return handler(req);
    // Keep pairing and unauthorized commands free of database access.
    if (mode === 'admin' && (message.chat.type !== 'private' ||
        String(message.chat.id) !== String(from.id) ||
        !(env.TG_ADMIN_USER_IDS||'').split(',').map(x=>x.trim()).includes(String(from.id)))) {
      return handler(req);
    }
    const claim = crypto.randomUUID();
    const base = env.SUPABASE_URL.replace(/\/+$/, '')+'/rest/v1/';
    const headers = {'Content-Type':'application/json',apikey:env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization:'Bearer '+env.SUPABASE_SERVICE_ROLE_KEY};
    const run = async(path,method,body) => {
      const response = await fetcher(base+path,{method,headers,body:JSON.stringify(body),
        signal:AbortSignal.timeout(8000)});
      if (!response.ok) throw new Error('Update store unavailable');
      return response;
    };
    const path = 'nca_bot_updates?bot=eq.'+mode+'&update_id=eq.'+update.update_id+'&claim=eq.'+claim;
    let claimed = false;
    try {
      const result = await (await run('rpc/claim_nca_bot_update','POST',{
        p_bot:mode,p_update_id:update.update_id,p_claim:claim,
      })).json();
      if (result === 'completed') return Response.json({ok:true,duplicate:true});
      if (result !== 'claimed') return Response.json({error:'Update in progress'}, {status:503});
      claimed = true;
      const response = await handler(req);
      if (!response.ok) throw new Error('Update not completed');
      await run(path,'PATCH',{completed:true});
      return response;
    } catch (_) {
      if (claimed) {
        try {await run(path,'DELETE');} catch (_) { /* Lease expires for retry. */ }
      }
      return Response.json({error:'Please retry this update'}, {status:503});
    }
  };
}
