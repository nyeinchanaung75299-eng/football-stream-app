import {test} from 'node:test';import assert from 'node:assert/strict';
import {parseXoilac,parseCamel,websiteMatches,websiteStreams} from '../supabase/functions/_shared/website_sources.mjs';
const now=Date.parse('2026-10-28T17:00:00Z');
const page='https://xoilaczcb.tv/truc-tiep/home-vs-away-luc-0000-ngay-29-10-2026/';
const xoi=`<div class="grid-matches__item grid-matches__item-match" data-fid="abc" data-runtime="${now/1000}" data-status="2" data-sport="football"><a href="${page}" title="Home vs Away lúc 00:00 ngày 29/10/2026" class="redirectPopup"></a><div class="grid-match__league"><span>League</span></div>`;
test('Xoilac public metadata deduplicates and excludes stale/nonfootball fixtures',()=>{
 const rows=parseXoilac(xoi+xoi+xoi.replace('data-sport="football"','data-sport="basketball"'),now);
 assert.equal(rows.length,1);assert.equal(rows[0].home_team,'Home');assert.equal(rows[0].status,'LIVE');assert.equal(rows[0].page_url,page);assert.equal(parseXoilac(xoi,now+5*3600000).length,0);
});
test('Camel reads literal Next metadata, not JS execution or account data',()=>{
 const payload={matchData:{living_group:[{competition:{name_en:'League'},match:[{id:'fixture123',match_time:now/1000,status_id:4,home_team:{name_en:'Home'},away_team:{name_en:'Away'}}]}]}};
 const html=`<a href="/football/match-home-vs-away/live/fixture123"></a><script>self.__next_f.push([1,${JSON.stringify('12:'+JSON.stringify(payload))}])</script>`;
 const rows=parseCamel(html,now);assert.equal(rows.length,1);assert.equal(rows[0].requires_login,true);assert.equal(rows[0].home_team,'Home');
});
test('Camel streams explicitly require provider login and perform no fetch',async()=>{
 const result=await websiteStreams('camel',{}, {fetcher:()=>{throw Error('must not fetch login/media')}});
 assert.equal(result.requires_login,true);assert.equal(result.ok,false);assert.deepEqual(result.lines,[]);
});
test('Xoilac accepts only published player and media hosts, never arbitrary targets',async()=>{
 const calls=[];const fetcher=async url=>{calls.push(url);return new Response(url===page?'var list_stream = [["https://xlz.domainkqt.cc/ajax/chanel/type/7/link/channel1","http://127.0.0.1/private"]];':'var urlStream = "https://live1.quickscoreboardz.com/live/channel1.flv?expires=1";');};
 const result=await websiteStreams('xoilac',{page_url:page},{fetcher});assert.equal(result.lines.length,1);assert.equal(result.lines[0].stream_type,'flv');assert.equal(calls.length,2);
 for(const target of ['http://127.0.0.1/','https://xoilaczcb.tv@evil.com/truc-tiep/abc/','https://xoilaczcb.tv/wp-admin/'])await assert.rejects(()=>websiteStreams('xoilac',{page_url:target},{fetcher}));
 const denied=await websiteStreams('xoilac',{page_url:page},{fetcher:async url=>new Response(url===page?'var list_stream=[["https://xlz.domainkqt.cc/ajax/chanel/type/7/link/channel1"]];':'var urlStream="http://127.0.0.1/live.m3u8";')});assert.equal(denied.lines.length,0);
});
test('provider failures and redirects do not become empty successful catalogs',async()=>{
 for(const status of [302,403,500])await assert.rejects(()=>websiteMatches('xoilac',{fetcher:async()=>new Response('',{status})}));
});


test('canonical Camel redirect stays same-origin and does not enter account routes', async()=>{
 const fixture={matchData:{living_group:[]}};
 const html='<script>self.__next_f.push([1,'+JSON.stringify('1:'+JSON.stringify(fixture))+'])</script>';
 const seen=[];
 const rows=await websiteMatches('camel',{fetcher:async url=>{seen.push(String(url));return seen.length===1?new Response('',{status:307,headers:{Location:'/en'}}):new Response(html);}});
 assert.deepEqual(rows,[]);assert.equal(seen.length,2);assert.equal(seen[1],'https://www.camel1.tv/en');
 await assert.rejects(()=>websiteMatches('camel',{fetcher:async()=>new Response('',{status:307,headers:{Location:'https://evil.invalid/account'}})}));
});
