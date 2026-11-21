import test from 'node:test';import assert from 'node:assert/strict';
import {parseFawaCatalog,isFawaFootball} from '../supabase/functions/_shared/fawa_catalog.mjs';
const card=(name,league,time)=>`<a href="/${encodeURIComponent(name)}.html"><div class="user-item__name">${name}</div><div class="user-item__playing">${league} ${time}</div></a>`;
test('Fawa excludes other sports even when title includes Football',()=>{
 for(const league of ['NCAA American Football','Cricket','NBA Basketball','Basketball NBL','BKFC Fight Night','Boxing','Australian Rules Football','Unknown'])assert.equal(isFawaFootball(league),false);
 const data=parseFawaCatalog('Schedule (GMT+1)'+card('A vs B','Japan J League','09:00')+card('C vs D','NCAA American Football','08:00'));
 assert.equal(data.length,1);assert.equal(data[0].sport,'football');
});
test('Fawa clocks sort through Myanmar midnight and never invent a date',()=>{
 const rows=parseFawaCatalog('Schedule (GMT+1)'+card('Late vs Other','Premier League','23:00')+card('Early vs Other','Japan J League','17:00'));
 assert.equal(rows[0].home_team,'Early');assert.equal(rows[1].time_label,'Premier League • 4:30 AM MMT (+1 day)');
 assert.ok(rows.every(r=>r.match_time===null&&!r.schedule_date_verified));
});
test('Fawa groups published channels and rejects foreign links',()=>{
 const rows=parseFawaCatalog('Schedule (GMT+1)'+card('Home vs Away','Japan J League','08:00')+card('Home vs Away --- CH 2','Japan J League','08:00'));
 assert.equal(rows.length,1);assert.equal(rows[0].anchors.length,2);
 assert.equal(parseFawaCatalog('Schedule (GMT+1)'+card('Home vs Away','Japan J League','08:00').replace('href="/','href="https://outside.example/')).length,0);
});
