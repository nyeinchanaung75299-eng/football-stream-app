-- Preserve a verified XMLTV display name when a repository refresh supplies
-- an event title. The display name belongs to this exact source/station pair.
alter table public.channels add column epg_display_name text;
alter table public.channels add constraint channel_epg_display_name_length
 check(epg_display_name is null or length(epg_display_name) between 1 and 120);

create function public.normalize_channel_station_name(p_name text)
returns text language plpgsql immutable strict set search_path='' as $$
declare value text:=btrim(p_name); candidate text; parts text[];
 brand text:='(?:beIN|DAZN|CBS|Sky[[:space:]]*Sports?|TNT[[:space:]]*Sports?|Fubo|FanCode|CazéTV|FOX[[:space:]]*Sports?|ESPN|NBC|USA[[:space:]]+(?:Network|Sports)|Peacock|Premier[[:space:]]+Sports|Paramount[+]?|LaLiga|SPOTV|Sport[[:space:]]*[12]|Ziggo|Eurosport|Tennis[[:space:]]+Channel|Willow|Setanta|Arena[[:space:]]+Sport|TSN|UFC)';
begin
 -- Repair a reversible UTF-8/Latin-1 decoding mistake only; valid accented
 -- names are kept. A failed conversion never discards the original name.
 if value ~ '[ÃÂ]' then
  begin candidate:=convert_from(convert_to(value,'LATIN1'),'UTF8');value:=candidate;
  exception when others then null; end;
 end if;
 if value ~* '^[0-9]{1,2}:[0-9]{2}[[:space:]]*(WIB|WITA|WIT|UTC|MMT)\M' then
  parts:=regexp_match(value,'\m(?:Football|Soccer|Cricket|Basketball|Tennis|Motorsports?|Rugby|Boxing)[[:space:]]+(.+)$','i');
  if parts is not null and parts[1] ~* ('^'||brand||'\M') then value:=parts[1];end if;
 elsif value ~* '\m(?:vs[.]?|versus)\M' then
  parts:=regexp_match(value,'(?:[•|]| - )[[:space:]]*('||brand||'.*)$','i');
  if parts is not null then value:=parts[1];end if;
 end if;
 value:=regexp_replace(value,'[[:space:]]*[-•][[:space:]]*(AQ|LQ|ALT|Main|Backup)[[:space:]]*$','','i');
 value:=btrim(regexp_replace(value,'[[:space:]]+',' ','g'));
 return case when value='' then btrim(p_name) else left(value,120) end;
end $$;
revoke all on function public.normalize_channel_station_name(text) from public,anon;
grant execute on function public.normalize_channel_station_name(text) to authenticated,service_role;

create function public.keep_channel_station_name()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if row(new.epg_source,new.epg_id) is distinct from row(old.epg_source,old.epg_id)
    and new.epg_display_name is not distinct from old.epg_display_name then
   new.epg_display_name:=null;
  end if;
 end if;
 if nullif(btrim(new.epg_source),'') is null or nullif(btrim(new.epg_id),'') is null then
  new.epg_display_name:=null;
 end if;
 new.epg_display_name:=nullif(btrim(new.epg_display_name),'');
 if new.epg_display_name is not null then new.name:=new.epg_display_name;
 else new.name:=public.normalize_channel_station_name(new.name);end if;
 return new;
end $$;
revoke all on function public.keep_channel_station_name() from public,anon,authenticated;
create trigger keep_channel_station_name before insert or update of name,epg_id,epg_source,epg_display_name
 on public.channels for each row execute function public.keep_channel_station_name();

comment on column public.channels.epg_display_name is
 'Verified display-name from the bound XMLTV station. Cleared when its source or station changes; preserved across repository name refreshes.';
notify pgrst,'reload schema';
