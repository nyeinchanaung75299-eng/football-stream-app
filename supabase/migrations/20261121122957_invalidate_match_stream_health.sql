-- A configuration edit invalidates the previous request/playlist check, even
-- when it was made outside the new batch importer. Historical failure totals
-- remain history; the changed playback configuration starts unverified.
create function private.invalidate_match_stream_health() returns trigger
 language plpgsql security invoker set search_path='' as $$
begin
 if public.stream_configuration_hash(to_jsonb(old))<>public.stream_configuration_hash(to_jsonb(new))
  or old.use_webview is distinct from new.use_webview
  or old.webview_url is distinct from new.webview_url
  or old.channel_line_id is distinct from new.channel_line_id then
  new.health_status:='unknown';
  new.last_checked_at:=null;
  new.health_latency_ms:=null;
 end if;
 return new;
end $$;
revoke all on function private.invalidate_match_stream_health() from public,anon,authenticated;
create trigger invalidate_match_stream_health before update of stream_url,stream_type,referer,origin,key_id,key_data,use_webview,webview_url,channel_line_id
 on public.stream_links for each row execute function private.invalidate_match_stream_health();
