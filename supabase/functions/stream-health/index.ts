import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { probeStreamFirstChunk } from "../_shared/stream_probe.mjs";
import { probeChannelMedia } from "../_shared/channel_media_probe.mjs";
import { sourceHash } from "../_shared/darkbyte_catalog.mjs";

type LinkRow = {
  id: string;
  match_id: string;
  stream_url: string | null;
  referer: string | null;
  origin: string | null;
  use_webview: boolean | null;
  webview_url: string | null;
};

type ChannelLineRow = {
  id: string;
  channel_id: string;
  stream_url: string | null;
  referer: string | null;
  origin: string | null;
  stream_type?: string;
  key_id?: string | null;
  key_data?: string | null;
};

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const cronSecret = Deno.env.get("CRON_SECRET");

    if (!supabaseUrl || !serviceRole) {
      return json({ error: "Supabase server credentials are missing." }, 500);
    }

    let cronAuthorized =
      !!cronSecret &&
      req.headers.get("x-cron-secret") === cronSecret;

    const admin = createClient(supabaseUrl, serviceRole);
    const pulse = req.headers.get('x-nca-channel-source-key');
    let healthWorker = false;
    if (pulse && /^[a-f\d]{64}$/i.test(pulse)) {
      const {data: auth} = await admin.from('channel_source_sync_auth').select('secret_sha256').eq('id',1).maybeSingle();
      healthWorker = auth?.secret_sha256 === await sourceHash(pulse);
      cronAuthorized ||= healthWorker;
    }
    let adminAuthorized = false;

    if (!cronAuthorized && anonKey) {
      const authHeader = req.headers.get("Authorization") ?? "";

      if (authHeader.startsWith("Bearer ")) {
        const userClient = createClient(supabaseUrl, anonKey, {
          global: {
            headers: {
              Authorization: authHeader,
            },
          },
        });

        const {
          data: { user },
          error: userError,
        } = await userClient.auth.getUser();

        if (!userError && user) {
          const { data: profile } = await userClient
            .from("profiles")
            .select("role")
            .eq("id", user.id)
            .single();

          adminAuthorized = profile?.role === "admin";
        }
      }
    }

    if (!cronAuthorized && !adminAuthorized) {
      return json({ error: "Admin or cron access required." }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const linkId = body?.link_id?.toString();
    const matchId = body?.match_id?.toString();
    const channelLineId = body?.channel_line_id?.toString();
    const channelId = body?.channel_id?.toString();
    const checkAll = body?.all === true || cronAuthorized;

    const rpc = async (name: string, fields: Record<string,unknown> = {}) => {
      const {data,error} = await admin.rpc(name,fields); if(error)throw new Error('Health operation failed');return data;
    };
    const action = String(body.action || '');
    if (healthWorker && action !== 'work') return json({error:'Worker access only'},403);
    if (action === 'work') {
      if (!cronAuthorized) return json({error:'Worker authorization required'},403);
      const items = await rpc('claim_channel_health_items',{p_limit:24}) || [];
      let cursor=0;
      await Promise.all(Array.from({length:6},async()=>{while(cursor<items.length){
        const item=items[cursor++];
        const result=item.configuration ? await probeChannelMedia(item.configuration) : {
          health_status:'unknown',http_status:0,latency_ms:0,manifest_status:'not_tested',segment_status:'not_tested',drm_status:'unknown',detail:'Line removed',
        };
        await rpc('finish_channel_health_item',{p_item:item.item_id,p_hash:item.config_hash,p_result:result});
      }}));
      const job=await rpc('channel_health_job_status');
      if(items.length && job.status==='running'){
        const next=fetch(supabaseUrl+'/functions/v1/stream-health',{method:'POST',
          headers:{'Content-Type':'application/json',...(pulse?{'x-nca-channel-source-key':pulse}:{'x-cron-secret':cronSecret||''})},
          body:JSON.stringify({action:'work'}),signal:AbortSignal.timeout(55000),
        }).then(response=>response.body?.cancel()).catch(()=>{});
        EdgeRuntime.waitUntil(next);
      }
      return json({ok:true,processed:items.length,job});
    }
    if (action) {
      if(!adminAuthorized)return json({error:'Admin access required'},403);
      if(action==='start_job'){
        await rpc('start_channel_health_job',{p_mode:String(body.mode||'all')});
        return json({ok:true,job:await rpc('channel_health_job_status')});
      }
      if(action==='job_status')return json({ok:true,job:await rpc('channel_health_job_status')});
      if(['pause_job','resume_job','cancel_job'].includes(action)){
        const status=action==='pause_job'?'paused':action==='resume_job'?'running':'cancelled';
        const {error}=await admin.from('channel_health_jobs').update({status,updated_at:new Date().toISOString()})
          .eq('id',String(body.job_id)).in('status',['running','paused']);
        if(error)throw new Error('Could not change scan state');
        if(status==='running')await rpc('request_channel_health_worker');
        return json({ok:true,job:await rpc('channel_health_job_status')});
      }
      if(action==='preview' || action==='record_playback'){
        const id=String(body.channel_line_id||'');
        if(!/^[a-f\d-]{36}$/i.test(id))return json({error:'Invalid channel line'},400);
        const {data:line,error}=await admin.from('channel_lines').select('id,label,stream_url,stream_type,referer,origin,key_id,key_data').eq('id',id).single();
        if(error||!line)return json({error:'Channel line unavailable'},404);
        const version=await rpc('channel_line_config_hash',{p_id:id});
        if(action==='preview')return json({ok:true,line,version});
        if(body.version!==version)return json({error:'Source changed; test the current line'},409);
        const status=String(body.status);
        if(!['verified','failed','unsupported'].includes(status))return json({error:'Invalid playback result'},400);
        if(status==='verified' && !(Number(body.frames)>0 && Number(body.width)>0 && Number(body.height)>0 && Number(body.advanced)>0.2))
          return json({error:'Decoded video frames required'},400);
        const {error:updateError}=await admin.from('channel_lines').update({playback_status:status,playback_device:String(body.device||'Admin').slice(0,30),last_playback_checked_at:new Date().toISOString()}).eq('id',id);
        if(updateError)throw new Error('Could not store playback result');
        return json({ok:true});
      }
      return json({error:'Unknown health action'},400);
    }

    // Channel-line checks are explicitly scoped to one private channel or
    // line. They never return a stream URL, referer, key, or playback token.
    if (channelLineId || channelId) {
      let channelQuery = admin
        .from("channel_lines")
        .select("id,channel_id,stream_url,stream_type,referer,origin,key_id,key_data")
        .eq("is_active", true)
        .order("sort_order", { ascending: true })
        .limit(channelLineId ? 1 : 30);

      if (channelLineId) {
        channelQuery = channelQuery.eq("id", channelLineId);
      } else if (channelId) {
        channelQuery = channelQuery.eq("channel_id", channelId);
      }

      const { data, error } = await channelQuery;
      if (error) throw error;
      const lines = (data ?? []) as ChannelLineRow[];
      const results: Record<string, unknown>[] = [];

      for (let offset = 0; offset < lines.length; offset += 4) {
        const chunk = lines.slice(offset, offset + 4);
        const checked = await Promise.all(
          chunk.map((line) => checkChannelLine(admin, line)),
        );
        results.push(...checked);
      }

      if (channelLineId && results.length === 1) {
        return json({ ok: true, ...results[0] });
      }
      return json({
        ok: true,
        checked: results.length,
        summary: healthSummary(results),
        results,
      });
    }

    let query = admin
      .from("stream_links")
      .select(
        "id,match_id,stream_url,referer,origin,use_webview,webview_url",
      )
      .eq("is_active", true)
      .order("priority", { ascending: true })
      .limit(checkAll ? 100 : 30);

    if (linkId) {
      query = query.eq("id", linkId);
    } else if (matchId) {
      query = query.eq("match_id", matchId);
    } else if (!checkAll) {
      return json(
        { error: "link_id, match_id, or all=true is required." },
        400,
      );
    }

    const { data, error } = await query;
    if (error) throw error;

    const links = (data ?? []) as LinkRow[];

    const results: Record<string, unknown>[] = [];

    for (let offset = 0; offset < links.length; offset += 4) {
      const chunk = links.slice(offset, offset + 4);
      const checked = await Promise.all(
        chunk.map((link) => checkLink(admin, link)),
      );
      results.push(...checked);
    }

    if (linkId && results.length === 1) {
      return json({ ok: true, ...results[0] });
    }

    return json({
      ok: true,
      checked: results.length,
      summary: healthSummary(results),
      results,
    });
  } catch (error) {
    console.error(error);
    return json(
      {
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});

async function checkLink(
  admin: SupabaseClient,
  link: LinkRow,
) {
  const url = link.use_webview ? link.webview_url : link.stream_url;

  let health = "failed";
  let statusCode = 0;
  let latency = 0;
  let detail = "";

  if (!url) {
    detail = "URL is empty.";
  } else {
    const headers: Record<string, string> = {
      "Accept": "*/*",
      "Range": "bytes=0-4095",
      "User-Agent": "FootballStreamHealth/1.0",
    };

    if (link.referer) headers["Referer"] = link.referer;
    if (link.origin) headers["Origin"] = link.origin;

    const result = await probeStreamFirstChunk(url, { headers });
    health = result.status;
    statusCode = result.httpStatus;
    latency = result.latencyMs;
    detail = result.detail;
  }

  const checkedAt = new Date().toISOString();

  await admin
    .from("stream_links")
    .update({
      health_status: health,
      health_latency_ms: latency,
      last_checked_at: checkedAt,
    })
    .eq("id", link.id);

  return {
    id: link.id,
    match_id: link.match_id,
    health_status: health,
    latency_ms: latency,
    http_status: statusCode,
    checked_at: checkedAt,
    detail,
  };
}

async function checkChannelLine(
  admin: SupabaseClient,
  line: ChannelLineRow,
) {
  const before = await admin.rpc('channel_line_config_hash',{p_id:line.id});
  const media = await probeChannelMedia(line);
  const result = {health:media.health_status,latency:media.latency_ms,statusCode:media.http_status};
  const checkedAt = new Date().toISOString();
  const after = await admin.rpc('channel_line_config_hash',{p_id:line.id});
  if(before.error || after.error || before.data!==after.data)return {id:line.id,channel_id:line.channel_id,health_status:'unknown',detail:'Source changed during check'};

  await admin
    .from("channel_lines")
    .update({
      health_status: result.health,
      health_latency_ms: result.latency,
      health_http_status: result.statusCode,
      last_checked_at: checkedAt,
      manifest_status:media.manifest_status,segment_status:media.segment_status,drm_status:media.drm_status,health_detail:media.detail,
    })
    .eq("id", line.id);

  return {
    id: line.id,
    channel_id: line.channel_id,
    health_status: result.health,
    latency_ms: result.latency,
    http_status: result.statusCode,
    checked_at: checkedAt,
    manifest_status:media.manifest_status,segment_status:media.segment_status,drm_status:media.drm_status,
  };
}

async function probe(
  url: string | null,
  referer: string | null,
  origin: string | null,
) {
  if (!url) {
    return {
      health: "failed",
      statusCode: 0,
      latency: 0,
      detail: "URL is empty.",
    };
  }
  const headers: Record<string, string> = {
    "Accept": "*/*",
    "Range": "bytes=0-4095",
    "User-Agent": "FootballStreamHealth/1.0",
  };
  if (referer) headers["Referer"] = referer;
  if (origin) headers["Origin"] = origin;
  const result = await probeStreamFirstChunk(url, { headers });
  return {
    health: result.status,
    statusCode: result.httpStatus,
    latency: result.latencyMs,
    detail: result.detail,
  };
}

function healthSummary(results: Record<string, unknown>[]) {
  return {
    healthy: results.filter((x) => x.health_status === "healthy").length,
    slow: results.filter((x) => x.health_status === "slow").length,
    failed: results.filter((x) => x.health_status === "failed").length,
    unknown: results.filter((x) => x.health_status === "unknown").length,
  };
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
