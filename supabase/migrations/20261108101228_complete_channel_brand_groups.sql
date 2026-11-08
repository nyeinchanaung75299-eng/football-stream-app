-- Distinguish known broadcaster families from anonymous extra/test slots.
-- Do not infer a country or EPG station from a generic Server 1 label.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.channel_group_name(text,text)'::regprocedure);
 if strpos(definition,'select case')=0 then raise exception 'Channel classifier hook unavailable'; end if;
 definition:=replace(definition,'select case',$rules$
 select case
 when p_name ~* '\mfs\s+[12]\M' then 'FOX Sports'
 when p_name ~* '\mbbc\M' then 'BBC'
 when p_name ~* '\mitv\M' then 'ITV'
 when p_name ~* '\mtve\M' then 'TVE'
 when p_name ~* '\mrte\M' then 'RTÉ'
 when p_name ~* '\mcnbc\M' then 'News'
 when p_name ~* '^canel\s*\+' then 'Canal+'
 when p_name ~* '^(prime\s*(eng|hindi|video))' then 'Prime Video'
 when p_name ~* 'mewatch' then 'MeWatch'
 when p_name ~* 'stan sports' then 'Stan Sports'
 when p_name ~* 'starzplay' then 'StarzPlay'
 when p_name ~* '^stc\s*(cinema|drama|family|trailer)' then 'Entertainment'
 when p_name ~* 'telemundo|telenovelas' then 'Telemundo'
 when p_name ~* '(^|[• ])(inter tv|milan tv|real madrid tv|mu tv)' then 'Club TV'
 when p_name ~* 'rugb(y|ypass)|wales v japan' then 'Rugby'
 when p_name ~* 'pickleball|ppa tour' then 'Pickleball'
 when p_name ~* 'netball' then 'Netball'
 when p_name ~* 'poker' then 'Poker'
 when p_name ~* 'bassmaster|fishing' then 'Fishing'
 when p_name ~* '\micc\M' then 'Cricket'
 when p_name ~* '^(fifa|fussball|ucl tv|epl\s*[0-9]|premier league\s*[0-9])' then 'Football'
 when p_name ~* 'one\s*sports?' then 'One Sports'
 when p_name ~* '^red\s*bull' then 'Red Bull'
 when p_name ~* '^ryz sports' then 'RYZ Sports'
 when p_name ~* '^psn\s*[0-9]' then 'PSN Sports'
 when p_name ~* '^unbeaten' then 'Unbeaten'
 when p_name ~* '^event\s*[0-9]|^iad live' then 'Live Events'
 when p_name ~* '^test\s*[0-9]' then 'Test Lines'
 when p_name ~* '^(server|link|extra)\s*[0-9]|^hd( stream|[0-9])?$|^aq$' then 'Extra Servers'
 $rules$);
 execute definition;
end $$;
update public.channels set category=public.channel_group_name(name,category) where not category_locked;
notify pgrst,'reload schema';
