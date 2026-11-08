import {test} from 'node:test';
import assert from 'node:assert/strict';
import {findVerifiedGuideMatches} from '../supabase/functions/_shared/nca_epg_auto_match.mjs';
test('NBC hosted-match description matches both teams and time, excludes previews and other opponents',()=>{
 const id='11111111-1111-4111-8111-111111111111',channel='22222222-2222-4222-8222-222222222222';
 const match={id,home_team:'Nottingham Forest',away_team:'Manchester City',kickoff_at:'2026-11-07T17:30:00Z',is_active:true,publish_state:'published'};
 const channels=[{id:channel,is_active:true,epg_id:'NBC.East.Stream.us2',epg_source:'US2'}];
 const pg={start:Date.parse(match.kickoff_at),title:'Live: Premier League Soccer',description:'Nottingham Forest host Manchester City in Matchweek 10.'};
 const guide=description=>({channels:[{id:channel,matchedEPG:true,programmes:[{...pg,description}]}]});
 const run=description=>findVerifiedGuideMatches([match],guide(description),channels,new Date('2026-11-07T17:00:00Z'));
 assert.equal(run(pg.description).length,1);
 assert.equal(run('Preview: '+pg.description).length,0);
 assert.equal(run('Nottingham Forest host Manchester United.').length,0);
 assert.equal(findVerifiedGuideMatches([match],{channels:[{id:channel,matchedEPG:true,programmes:[{...pg,start:pg.start+86400000}]}]},channels,new Date('2026-11-07T17:00:00Z')).length,0);
});
