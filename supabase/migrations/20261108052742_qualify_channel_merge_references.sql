-- The merge cursor is named source; qualify the optional bot table columns
-- so legacy production tables use their fields instead of the PL/pgSQL cursor.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.deduplicate_exact_channel_lines()'::regprocedure);
 if strpos(definition,'select match_id,item.keep_channel,source,created_at from public.nca_bot_match_channels where channel_id=item.channel_id')=0 then
  raise exception 'Channel merge reference hook unavailable';
 end if;
 definition:=replace(definition,
  'select match_id,item.keep_channel,source,created_at from public.nca_bot_match_channels where channel_id=item.channel_id',
  'select b.match_id,item.keep_channel,b.source,b.created_at from public.nca_bot_match_channels b where b.channel_id=item.channel_id');
 execute definition;
end $$;
notify pgrst,'reload schema';
