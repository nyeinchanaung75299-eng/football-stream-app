const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const clean = value => String(value||'').replace(/[\u0000-\u001f]/g,' ').slice(0,90);

export function createViewerFeatures({env, fetcher=fetch, clock=()=>new Date(), site}) {
  const headers = {apikey:env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization:'Bearer '+env.SUPABASE_SERVICE_ROLE_KEY,'Content-Type':'application/json'};
  async function db(path, method='GET', body, prefer='return=representation') {
    const response = await fetcher(env.SUPABASE_URL.replace(/\/+$/,'')+'/rest/v1/'+path,{
      method,headers:{...headers,Prefer:prefer},
      ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error('Viewer data unavailable');
    return response.status===204 ? [] : response.json();
  }
  async function match(id) {
    if (!UUID.test(id)) return null;
    const rows=await db('matches?select=id,home_team,away_team,kickoff_at&id=eq.'+id+
      '&is_active=eq.true&publish_state=eq.published&deleted_at=is.null&is_finished=eq.false&limit=1');
    return rows[0]||null;
  }
  async function handle(raw, chatId) {
    if (raw==='/reminders' || raw==='/unsubscribe') {
      if (raw==='/unsubscribe') {
        await db('nca_viewer_reminders?chat_id=eq.'+chatId,'DELETE');
        return {text:'All your match reminders are cancelled.'};
      }
      const rows=await db('nca_viewer_reminders?select=match_id,due_at&chat_id=eq.'+chatId+
        '&delivered_at=is.null&order=due_at.asc&limit=50');
      return {text:rows.length+' active reminders. Choose a match in /today or /schedule to add one.\n/unsubscribe cancels all reminders.',
        keyboard:{inline_keyboard:rows.map(r=>[{text:'Cancel '+new Date(r.due_at).toLocaleString('en-GB',{timeZone:'Asia/Yangon'}),
          callback_data:'cancel:'+r.match_id}])}};
    }
    const action=raw.match(/^(remind|cancel|report|broken):(.+)$/);
    if (!action || !UUID.test(action[2])) return null;
    const [,kind,id]=action;
    if (kind==='remind' || kind==='cancel') {
      if (kind==='cancel') {
        await db('nca_viewer_reminders?chat_id=eq.'+chatId+'&match_id=eq.'+id,'DELETE');
        return {text:'Reminder cancelled.'};
      }
      const fixture=await match(id);
      const kickoff=new Date(fixture?.kickoff_at).valueOf();
      if (!fixture || !Number.isFinite(kickoff) || kickoff<=clock().valueOf())
        return {text:'This match has started or is no longer available.'};
      const count=await db('nca_viewer_reminders?select=match_id&chat_id=eq.'+chatId+'&delivered_at=is.null&limit=50');
      if (count.length>=50 && !count.some(r=>r.match_id===id)) return {text:'You have 50 reminders. Cancel an old reminder in /reminders first.'};
      await db('nca_viewer_reminders?on_conflict=chat_id,match_id','POST',{
        chat_id:chatId,match_id:id,due_at:new Date(Math.max(clock().valueOf(),kickoff-10*60000)).toISOString(),
      },'resolution=ignore-duplicates,return=representation');
      return {text:'🔔 Reminder set for '+clean(fixture.home_team)+' vs '+clean(fixture.away_team)+
        '. We will send it about 10 minutes before kickoff.\n/reminders to manage; /unsubscribe to stop all.',
        keyboard:{inline_keyboard:[[{text:'Open match',url:site+'?match='+id},{text:'Cancel reminder',callback_data:'cancel:'+id}]]}};
    }
    if (kind==='report') {
      const channels=await db('channels?select=id,name&id=eq.'+id+'&is_active=eq.true&limit=1');
      if (!channels.length) return {text:'Channel is no longer available.'};
      const lines=await db('channel_lines?select=id,label&channel_id=eq.'+id+'&is_active=eq.true&order=sort_order&limit=20');
      return {text:'Report a broken line for '+clean(channels[0].name)+'. Select the line that failed:',
        keyboard:{inline_keyboard:lines.map((l,i)=>[{text:clean(l.label)||'Line '+(i+1),callback_data:'broken:'+l.id}])}};
    }
    const lines=await db('channel_lines?select=id,channel_id,label&id=eq.'+id+'&is_active=eq.true&limit=1');
    const line=lines[0];
    if (!line) return {text:'This line is no longer available.'};
    const channels=await db('channels?select=id,name&id=eq.'+line.channel_id+'&is_active=eq.true&limit=1');
    if (!channels.length) return {text:'This channel is no longer available.'};
    const recent=await db('nca_viewer_reports?select=id&chat_id=eq.'+chatId+'&created_at=gte.'+
      new Date(clock().valueOf()-3600000).toISOString()+'&limit=10');
    if (recent.length>=10) return {text:'You have sent 10 reports this hour. Please try again later.'};
    await db('nca_viewer_reports?on_conflict=chat_id,line_id,report_day','POST',{
      chat_id:chatId,channel_id:line.channel_id,line_id:id,
    },'resolution=ignore-duplicates,return=representation');
    return {text:'Report saved: '+clean(channels[0].name)+' • '+clean(line.label)+'. Thank you.'};
  }
  async function pulse(req) {
    const key=req.headers.get('x-nca-viewer-pulse-key')||'';
    if (!/^[a-f0-9]{64}$/.test(key)) return Response.json({error:'Unauthorized'}, {status:401});
    const stored=await db('nca_viewer_scheduler?select=secret_sha256&id=eq.1');
    const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(key));
    const digest=Array.from(new Uint8Array(bytes),x=>x.toString(16).padStart(2,'0')).join('');
    if (!stored[0] || stored[0].secret_sha256!==digest) return Response.json({error:'Unauthorized'}, {status:401});
    if (!env.TG_VIEWER_BOT_TOKEN) return Response.json({error:'Bot not configured'}, {status:503});
    const now=clock();
    const rows=await db('nca_viewer_reminders?select=chat_id,match_id&delivered_at=is.null&due_at=lte.'+
      now.toISOString()+'&or=(retry_after.is.null,retry_after.lt.'+now.toISOString()+')&order=due_at.asc&limit=20');
    let delivered=0;
    for (const r of rows) {
      const path='nca_viewer_reminders?chat_id=eq.'+r.chat_id+'&match_id=eq.'+r.match_id;
      // Claim a short delivery lease so overlapping scheduler calls cannot send twice.
      const claim=await db(path+'&delivered_at=is.null&or=(retry_after.is.null,retry_after.lt.'+now.toISOString()+')','PATCH',
        {retry_after:new Date(now.valueOf()+2*60000).toISOString()});
      if (!claim.length) continue;
      try {
        const fixture=await match(r.match_id);
        if (!fixture || new Date(fixture.kickoff_at).valueOf()<now.valueOf()-5*60000) {
          await db(path,'DELETE'); continue;
        }
        const result=await fetcher('https://api.telegram.org/bot'+env.TG_VIEWER_BOT_TOKEN+'/sendMessage',{
          method:'POST',headers:{'Content-Type':'application/json'},signal:AbortSignal.timeout(8000),
          body:JSON.stringify({chat_id:r.chat_id,text:'🔔 '+clean(fixture.home_team)+' vs '+clean(fixture.away_team)+
            '\n'+new Date(fixture.kickoff_at).toLocaleString('en-GB',{timeZone:'Asia/Yangon'})+' MMT',
            reply_markup:{inline_keyboard:[[{text:'Watch match',url:site+'?match='+r.match_id}]]}}),
        });
        const json=await result.json();
        if (result.status===403) {await db('nca_viewer_reminders?chat_id=eq.'+r.chat_id,'DELETE');continue;}
        if (!result.ok || !json.ok) throw new Error('Retry delivery');
        await db(path,'PATCH',{delivered_at:clock().toISOString()});delivered++;
      } catch (_) { /* Lease permits a bounded retry on a later pulse. */ }
    }
    return Response.json({ok:true,delivered});
  }
  return {handle,pulse};
}
