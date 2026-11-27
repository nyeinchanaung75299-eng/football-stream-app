-- Existing explicit import mappings still take precedence. New attachments
-- may only reuse a fixture from the same UTC kickoff and named competition.
do $migration$
declare
  definition text := pg_get_functiondef('public.publish_repository_match(text,timestamptz)'::regprocedure);
  old_filter text := 'm.kickoff_at between kickoff-interval ''30 minutes'' and kickoff+interval ''30 minutes''';
  new_filter text := $filter$m.kickoff_at = kickoff
    and regexp_replace(lower(m.league),'[^a-z0-9]','','g') =
        regexp_replace(lower(meta->>'league'),'[^a-z0-9]','','g')
    and regexp_replace(lower(meta->>'league'),'[^a-z0-9]','','g')
        not in ('', 'football', 'soccer', 'livesports', 'liveevent', 'liveevents')$filter$;
begin
  if (length(definition) - length(replace(definition, old_filter, ''))) <> 2 * length(old_filter) then
    raise exception 'Repository publish candidate filters changed';
  end if;
  execute replace(definition, old_filter, new_filter);
end
$migration$;
notify pgrst,'reload schema';
