#!/usr/bin/env python3
"""Public EPG metadata only: exact identities, regional checks, fresh programmes.

No playlist URL, playback token, DRM key or provider builder is fetched or
published. Missing/ambiguous stations remain unbound. Run with --propose only
for an operator audit; normal refreshes follow the saved channel bindings.
"""
import argparse
import concurrent.futures
import csv
import gzip
import io
import json
import re
import unicodedata
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

RAW = 'https://raw.githubusercontent.com/'
FEEDS = [
    ('talk_us', RAW+'acidjesuz/EPGTalk/master/US_lite.xml.gz', 'US'),
    ('talk_uk', RAW+'acidjesuz/EPGTalk/master/UK_lite.xml.gz', 'GB'),
    ('talk_mx', RAW+'acidjesuz/EPGTalk/master/Latino_lite.xml.gz', 'MX'),
    ('talk_sports', RAW+'acidjesuz/EPGTalk/master/Sports_guide.xml.gz', ''),
    ('talk_freetv', RAW+'acidjesuz/EPGTalk/master/FreeTV_guide.xml.gz', ''),
    ('bdix', RAW+'saeidrahmanbd/BDIX-IPTV/main/epg/epg.xml', ''),
    ('mjh_kayo', RAW+'matthuisman/i.mjh.nz/master/Kayo/epg.xml.gz', 'AU'),
    ('mjh_dstv', RAW+'matthuisman/i.mjh.nz/master/DStv/za.xml.gz', 'ZA'),
    ('mjh_nz', RAW+'matthuisman/i.mjh.nz/master/SkySportNow/epg.xml.gz', 'NZ'),
] + [('share_'+code, 'https://epgshare01.online/epgshare01/epg_ripper_'+code+'.xml.gz', country)
     for code, country in [('IN1','IN'),('IN4','IN'),('IT1','IT'),('FR1','FR'),('BR1','BR'),
                           ('PT1','PT'),('AR1','AR'),('ES1','ES'),('DE1','DE'),('TH1','TH'),
                           ('MY1','MY'),('NL1','NL'),('AE1','AE'),('CZ1','CZ'),('SK1','SK'),
                           ('PL1','PL'),('UK1','GB'),('US2','US'),('AU1','AU'),('MX1','MX'),('BEIN1','QA')]]
SOURCE_COUNTRIES = {'US2':'US','UK1':'GB','AU1':'AU','CZ1':'CZ','SK1':'SK','MY1':'MY',
                    'MX1':'MX','CA1':'CA','BR1':'BR','TVDANAS_BA':'BA'}
# Existing operator bindings use these exact XMLTV station IDs already.
# Publish their programme metadata too, so a cold regional API request does
# not temporarily hide an already verified NBC/TNT channel.
SAVED_FEEDS = {code:'share_'+code for code in ('US2','UK1','CZ1','SK1','MY1','BR1','AU1','MX1')}
COUNTRY_LABELS = {'usa':'US','united states':'US','uk':'GB','united kingdom':'GB','australia':'AU',
                  'canada':'CA','malaysia':'MY','germany':'DE','italia':'IT','italy':'IT',
                  'portugal':'PT','spain':'ES','france':'FR','bangladesh':'BD','nepal':'NP',
                  'brazil':'BR','brasil':'BR','thailand':'TH','pakistan':'PK','india':'IN',
                  'poland':'PL','italian':'IT','german':'DE','mexico':'MX'}
COUNTRY_CODES = {'UK':'GB','USA':'US','AUS':'AU','IND':'IN',
                 **{code:code for code in ('CZ','SK','AU','NZ','NL','BR','DE','IT','PL','ES','FR','MX','TH','NP','SG')}}

def text(value, limit=300):
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]*>', ' ', str(value or ''))).strip()[:limit]

def timestamp(value):
    match = re.fullmatch(r'(\d{14})\s*([+-]\d{4}|Z)', value or '')
    if not match:
        return None
    try:
        result = datetime.strptime(''.join(match.groups()).replace('Z','+0000'), '%Y%m%d%H%M%S%z')
        return int(result.timestamp()*1000)
    except ValueError:
        return None

def display_station(value):
    value = str(value or '')
    if '•' in value and re.search(r'\b(?:vs|v|versus)\b', value, re.I):
        value = value.rsplit('•', 1)[-1]
    if re.match(r'^\d{1,2}:\d{2}\s*(?:WIB|WITA|WIT|UTC|MMT)\b', value, re.I):
        event = re.search(r'\b(?:Football|Soccer|Cricket|Basketball|Tennis|Motorsports?|Rugby|Boxing)\s+(.+)$', value, re.I)
        if not event:
            return ''
        value = event[1]
    return value

def station_name(value):
    value = display_station(value)
    value = re.sub(r'\([^)]*(?:NITRO|Provider)[^)]*\)', ' ', value, flags=re.I)
    value = re.sub(r'\s*\(\d+\)\s*$', '', value)
    value = re.sub(r'\s*[-•]\s*(?:AQ|ALT|Main)\s*$', '', value, flags=re.I)
    value = re.sub(r'(?:(?<=\d)|\b)(?:'+ '|'.join(COUNTRY_CODES)+r')\s*$', '', value)
    value = unicodedata.normalize('NFKD', value).encode('ascii','ignore').decode().lower()
    value = re.sub(r'\b(?:'+ '|'.join(map(re.escape,COUNTRY_LABELS))+r')\b', ' ', value)
    # Dedicated UHD/4K feeds often carry event-only schedules instead of
    # the ordinary station's full guide. Keep those identities distinct.
    value = re.sub(r'\b(?:full\s*hd|fhd|hd|sd|aq|hevc|h264|h265|mpd|\d{3,4}p)\b', ' ', value)
    value = re.sub(r'\baq(?=\d)', '', value)
    value = re.sub(r'[^a-z0-9+]', '', value)
    value = re.sub(r'(?<!u)(?:fhd|hd|sd)$', '', value)
    equivalents = {'fs1':'foxsports1','fs2':'foxsports2','skysportspl':'skysportspremierleague',
                   'cbsgolazo':'cbssportsgolazonetwork','cbssportsgolazo':'cbssportsgolazonetwork',
                   'usatveast':'usanetworkeast','usawest':'usanetworkwest',
                   **{'adsports'+str(n):'abudhabisports'+str(n) for n in range(1,7)},
                   **{'sonyten'+str(n):'sonysportsten'+str(n) for n in range(1,6)}}
    value = value.replace('ziggosports','ziggosport')
    value = re.sub(r'^bein(?:sports?)?(?:english|eng)(\d+)$',r'beinsports\1english',value)
    return equivalents.get(value,value)

def country_hint(row):
    # Countries in the two fixture opponents are not broadcaster regions.
    name = display_station(row.get('name',''))
    flags = re.findall('[\U0001F1E6-\U0001F1FF]{2}', name)
    found = {''.join(chr(ord(c)-0x1F1E6+65) for c in flag) for flag in flags}
    for label, country in COUNTRY_LABELS.items():
        if re.search(r'\b'+re.escape(label)+r'\b', name, re.I):
            found.add(country)
    short=re.search(r'(?:(?<=\d)|\b)('+ '|'.join(COUNTRY_CODES)+r')\s*(?:[-•]\s*(?:AQ|FHD|HD|SD))?\s*$',name)
    if short:found.add(COUNTRY_CODES[short[1]])
    if len(found)==1:
        return found.pop()
    if found:
        return ''
    category = str(row.get('category','')).lower()
    if category in COUNTRY_LABELS:return COUNTRY_LABELS[category]
    if category == 'kolkata': return 'IN'
    if category == 'toffee content': return 'BD'
    source = row.get('epg_source','') or ''
    if source.startswith('IC_'): return source[3:]
    return SOURCE_COUNTRIES.get(source,'')

def read_url(url, limit=80*1024*1024):
    request = urllib.request.Request(url, headers={'User-Agent':'NCA-Public-EPG/1.0'})
    with urllib.request.urlopen(request, timeout=35) as response:
        data=response.read(limit+1)
    if len(data)>limit: raise ValueError('EPG exceeds download budget')
    return data

def official_directory(data):
    ids={}; aliases=defaultdict(set)
    for row in csv.DictReader(io.StringIO(data.decode('utf-8-sig'))):
        if row.get('closed') or row.get('replaced_by'): continue
        ids[row['id']]=row
        # Historical aliases can represent a rebrand with different content
        # (e.g. Ten Cricket versus today's Hindi Sony Ten 3). Only equivalent
        # current spelling/quality variants are used automatically.
        for name in [row['name'], *[n for n in row.get('alt_names','').split(';') if station_name(n)==station_name(row['name'])]]:
            key=station_name(name)
            if key: aliases[(key,row['country'])].add(row['id'])
    return ids,aliases

def read_feed(spec, cache, now):
    feed,url,country=spec
    suffix='.xml.gz' if url.endswith('.gz') else '.xml'
    path=cache/(feed+suffix)
    if not path.exists():
        path.write_bytes(read_url(url))
    channels={}; programmes=defaultdict(list)
    earliest=int((now-timedelta(hours=6)).timestamp()*1000)
    latest=int((now+timedelta(days=8)).timestamp()*1000)
    source=gzip.open(path,'rb') if suffix.endswith('gz') else open(path,'rb')
    with source:
        iterator=ET.iterparse(source,events=('start','end'))
        _,root=next(iterator)
        for event,node in iterator:
            if event!='end': continue
            if node.tag=='channel':
                identity=node.get('id','')
                names=[text(x.text) for x in node.findall('display-name') if x.text]
                # The provider distinguishes the English service from Arabic
                # and French services in its exact published station ID.
                english=re.fullmatch(r'beIN_SPORTS([123])_ENGLISH_Digital_Mono_EN\.bein',identity)
                if feed=='share_BEIN1' and english:
                    names.append('beIN Sports English '+english[1])
                channels[identity]={'id':identity,'names':names,
                                    'feed':feed,'country':country,'programmes':[]}
                node.clear()
            elif node.tag=='programme':
                start,end=timestamp(node.get('start')),timestamp(node.get('stop'))
                title=text(node.findtext('title'),180)
                if (start is not None and end is not None and earliest<=start<latest and
                    int(now.timestamp()*1000)<end and 0<end-start<=24*3600000 and title and
                    not re.fullmatch(r'(?i)(?:off air|no (?:epg|information|programme.*)|tba|not available|to be announced)',title)):
                    record={'start':start,'end':end,'title':title,
                            'subtitle':text(node.findtext('sub-title'),150),'description':text(node.findtext('desc'),240)}
                    programmes[node.get('channel','')].append(record)
                node.clear();root.clear()
    for identity,row in channels.items():
        unique={(p['start'],p['title']):p for p in programmes[identity]}
        row['programmes']=sorted(unique.values(),key=lambda p:p['start'])[:60]
    return [row for row in channels.values() if row['programmes']]

def candidate_index(feeds, official, aliases):
    index=defaultdict(list)
    regions=defaultdict(set)
    for key,country in aliases:regions[key].add(country)
    for row in feeds:
        keys={station_name(name) for name in row['names']}
        match=re.search(r'[._-]([a-z]{2})(?:[0-9]+)?$',row['id'],re.I)
        suffix=match[1].upper() if match and match[1].lower() not in ('org','com','tv') else ''
        explicit={country_hint({'name':name}) for name in row['names']}-{''}
        if len(explicit)>1:continue
        if suffix and explicit and suffix not in explicit:continue
        country=suffix or next(iter(explicit),'') or row['country']
        if row['feed'].startswith('talk_'):
            # The US file also carries Canadian stations; Latino combines
            # several countries. File location alone is not station proof.
            countries={c for key in keys for c in regions.get(key,())}
            allowed={'US','CA'} if row['feed'] in ('talk_us','talk_sports','talk_freetv') else {'GB','IE'} if row['feed']=='talk_uk' else {'MX','AR','BR','CO','CL','PE','UY','VE','EC','CR','DO','PA','HN','GT','SV','NI','PR'}
            if len(countries)!=1 or not countries.issubset(allowed):continue
            country=next(iter(countries))
        if country=='UK': country='GB'
        if not country: continue
        direct=official.get(row['id'])
        groups={direct['id']} if direct else set()
        for key in keys:
            groups.update(aliases.get((key,country),set()))
        # HD/SD spellings can be simulcasts; language and regional variants
        # remain distinct. Never merge different current station brands.
        identities={station_name(official[g]['name']) for g in groups}
        if len(identities)>1: continue
        group=next(iter(identities)) if identities else next(iter(sorted(keys-{''})),None)
        if not group: continue
        item={**row,'country':country,'station':group}
        for identity in groups:
            keys.add(station_name(official[identity]['name']))
        for key in keys-{''}: index[key].append(item)
    return index

def propose_binding(channel,index,official,aliases):
    key=station_name(channel.get('name'))
    if not key or key.isdigit() or 'unverified' in channel.get('name','').lower():return None,'no verified stable station name'
    country=country_hint(channel)
    official_countries={c for alias,c in aliases if alias==key}
    if not country and not official_countries:
        return None,'station identity needs regional confirmation'
    if not country and (len(official_countries)>1 or re.fullmatch(r'(?:fox(?:sports)?\d*|espn\d*|hbo\d*|bein(?:sports)?\d*|telemundo)',key)):
        return None,'region is ambiguous'
    if not country and re.fullmatch(r'skysports?\d*',key):
        return None,'regional or legacy numbered Sky station is ambiguous'
    if not country and re.fullmatch(r'(?:canal\+\d*|eurosport\d*|laligatv|realmadridtv)',key):
        return None,'regional or language variant needs confirmation'
    rows=index.get(key,[])
    if country: rows=[r for r in rows if r['country']==country]
    elif official_countries: rows=[r for r in rows if r['country'] in official_countries]
    groups={(r['country'],r['station']) for r in rows}
    if len(groups)!=1:return None,'ambiguous station or no fresh guide'
    selected=sorted(rows,key=lambda r:(-len(r['programmes']),r['feed'],r['id']))[0]
    return selected,'exact station identity'+(' and region' if country else '')

def saved_feed(source):
    return source[3:] if source.startswith('GH:') else SAVED_FEEDS.get(source)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--catalog',required=True)
    parser.add_argument('--cache-dir',required=True)
    parser.add_argument('--out',required=True)
    parser.add_argument('--propose',action='store_true')
    parser.add_argument('--audit')
    parser.add_argument('--previous')
    options=parser.parse_args()
    now=datetime.now(timezone.utc);cache=Path(options.cache_dir);cache.mkdir(parents=True,exist_ok=True)
    directory=cache/'official-channels.csv'
    if not directory.exists():directory.write_bytes(read_url(RAW+'iptv-org/database/master/data/channels.csv',5*1024*1024))
    official,aliases=official_directory(directory.read_bytes())
    payload=json.loads(Path(options.catalog).read_text())
    channels=payload.get('channels',[]) if isinstance(payload,dict) else payload
    statuses=[];all_rows=[]
    def load(spec):
        try:
            rows=read_feed(spec,cache,now)
            return rows,{'name':spec[0],'ok':bool(rows),'channels':len(rows)}
        except Exception:return [],{'name':spec[0],'ok':False,'channels':0}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for rows,status in pool.map(load,FEEDS):all_rows.extend(rows);statuses.append(status)
    index=candidate_index(all_rows,official,aliases)
    by_id={(r['feed'],r['id']):r for r in all_rows};output=[];audit=[]
    for channel in channels:
        source=channel.get('epg_source') or '';identity=channel.get('epg_id')
        feed=saved_feed(source)
        if feed:
            selected=by_id.get((feed,identity));reason='saved verified binding'
        elif options.propose and not source and not identity:
            selected,reason=propose_binding(channel,index,official,aliases)
        else:continue
        audit.append({'id':channel['id'],'name':channel['name'],'epg_source':source or 'GH:'+selected['feed'] if selected else None,
                      'epg_id':selected['id'] if selected else None,'reason':reason})
        if selected:output.append({'id':channel['id'],'name':channel['name'],'epg_name':selected['names'][0],'category':channel.get('category',''),
                                  'matchedEPG':True,'region':selected['country'].lower(),'programmes':selected['programmes'],
                                  'epg_id':selected['id'],'epg_source':source or 'GH:'+selected['feed'],'verified_at':now.isoformat()})
    # Retain a still-fresh saved binding during a temporary provider outage.
    # A changed station/source never inherits the previous station's guide.
    if options.previous and Path(options.previous).exists():
        previous=json.loads(Path(options.previous).read_text())
        try:age=now-datetime.fromisoformat(previous.get('updated_at',''))
        except (ValueError,TypeError):age=timedelta(days=10)
        current={c['id']:c for c in channels};present={c['id'] for c in output}
        if timedelta(0)<=age<timedelta(hours=18):
            for row in previous.get('channels',[]):
                saved=current.get(row.get('id'),{})
                try:row_age=now-datetime.fromisoformat(row.get('verified_at',previous.get('updated_at','')))
                except (ValueError,TypeError):continue
                if (row.get('id') not in present and saved.get('epg_source')==row.get('epg_source') and
                    saved.get('epg_id')==row.get('epg_id') and timedelta(0)<=row_age<timedelta(hours=18) and
                    any(p.get('end',0)>int(now.timestamp()*1000) for p in row.get('programmes',[]))):
                    output.append(row)
    result={'ok':True,'updated_at':now.isoformat(),'sources':statuses,'channels':output}
    encoded=json.dumps(result,separators=(',',':'),ensure_ascii=False)
    if len(encoded.encode())>2*1024*1024:raise ValueError('Matched public EPG exceeds metadata budget')
    if not output:raise ValueError('No fresh verified channel guide; keep the previous feed')
    Path(options.out).write_text(encoded)
    if options.audit:Path(options.audit).write_text(json.dumps(audit,ensure_ascii=False,indent=2))
    print(json.dumps({'catalog_channels':len(channels),'matched':len(output),'fresh_feed_channels':len(all_rows),'bytes':len(encoded.encode()),'sources':statuses}))

if __name__=='__main__':main()
