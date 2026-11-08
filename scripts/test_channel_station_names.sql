-- Real trigger behaviour: imports cannot replace an exact guide display name,
-- and a different station never inherits that display name.
begin;
do $$
declare channel uuid:=gen_random_uuid(); value text; saved_name text;
begin
 if public.normalize_channel_station_name('01:00 WIB AJ Auxerre vs Paris FC Football beIN ENGLISH - AQ')<>'beIN ENGLISH' then
  raise exception 'Fixture prefix was kept as a channel name';end if;
 if public.normalize_channel_station_name('Forest vs Manchester City • SKY SPORTS PL FHD')<>'SKY SPORTS PL FHD' then
  raise exception 'Named station was lost';end if;
 if public.normalize_channel_station_name('00:30 WIB Osasuna vs Athletic Club Football CazÃ©TV - AQ')<>'CazéTV' then
  raise exception 'Channel encoding was not repaired';end if;
 if public.normalize_channel_station_name('Stuttgart vs Bremen • Low')<>'Stuttgart vs Bremen • Low' then
  raise exception 'Unknown event feed was presented as a verified TV station';end if;
 insert into public.channels(id,name,epg_source,epg_id,epg_display_name)
  values(channel,'Repository title','fixture-guide','Sports1.au','Sports One Australia');
 update public.channels set name='Home vs Away • SPORTS ONE - AQ' where id=channel;
 select name into value from public.channels where id=channel;
 if value<>'Sports One Australia' then raise exception 'Repository overwrote the guide display name';end if;
 update public.channels set epg_id='Sports2.au' where id=channel;
 select epg_display_name into saved_name from public.channels where id=channel;
 if saved_name is not null then raise exception 'A changed station inherited the old guide name';end if;
 update public.channels set epg_display_name='Sports Two Australia',name='Source title' where id=channel;
 select name into value from public.channels where id=channel;
 if value<>'Sports Two Australia' then raise exception 'New verified display name was not used';end if;
end $$;
rollback;
