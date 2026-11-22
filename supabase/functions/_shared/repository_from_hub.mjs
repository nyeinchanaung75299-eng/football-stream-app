// The production Repository/Live 2 pipeline consumes the last committed Hub
// snapshot. It performs no GitHub requests and cannot modify operator lines.
import {parseRepositoryMatches,mergeRepositoryMatches} from './repository_matches.mjs';
import {sourceHash} from './darkbyte_catalog.mjs';
import {REPOSITORY_TREE_SOURCES} from './repository_trees.mjs';
const leagues = new Map([
 ['epl', 'Premier League'], ['premier league', 'Premier League'],
 ['laliga', 'LaLiga'], ['la liga', 'LaLiga'],
 ['laliga 2', 'LaLiga 2'], ['la liga 2', 'LaLiga 2'],
 ['ligue 1', 'Ligue 1'], ['serie a', 'Serie A'], ['bundesliga', 'Bundesliga'],
]);
function reviewedLeague(value) {
 return leagues.get(String(value || '').toLowerCase().replace(/[^a-z0-9 ]/g, '').trim());
}
function badgeId(value) {
 return /^https:\/\/img\.sofascore\.com\/api\/v1\/team\/(\d+)\/image(?:[?].*)?$/.exec(value || '')?.[1];
}
function fixtureEvidence(row) {
 const home = badgeId(row.home_logo_url), away = badgeId(row.away_logo_url);
 const league = reviewedLeague(row.league);
 return home && away && home !== away && league && row.kickoff_at
  ? JSON.stringify([league, home, away, row.kickoff_at, row.competition_tag || ''])
  : null;
}
function mergeVerifiedAliases(rows) {
 const groups = new Map();
 for (const row of rows) {
  const evidence = fixtureEvidence(row);
  if (!evidence) continue;
  const group = groups.get(evidence) || [];
  group.push(row);
  groups.set(evidence, group);
 }
 for (const group of groups.values()) {
  if (new Set(group.map(row => row.repository)).size < 2) continue;
  const canonical = [...group].sort((a, b) =>
   Number(a.repository === 'mdjamsad9/dudetvapi') - Number(b.repository === 'mdjamsad9/dudetvapi') ||
   (b.home_team.length + b.away_team.length) - (a.home_team.length + a.away_team.length) ||
   a.home_team.localeCompare(b.home_team) || a.away_team.localeCompare(b.away_team)
  )[0];
  for (const row of group) {
   row.home_team = canonical.home_team;
   row.away_team = canonical.away_team;
   row.league = canonical.league;
  }
 }
 return rows;
}
export async function repositoryMatchesFromHub(entries,{revision='',missingRepositories=[],complete=true,now=Date.now()}={}){
 const missing=new Set(!complete&&!missingRepositories.length?REPOSITORY_TREE_SOURCES:missingRepositories),rows=[];
 for(const entry of entries){
  if(entry.kind!=='event')continue;
  const meta=entry.event_meta||{},repository=meta.source_repository;
  if(!repository||missing.has(repository)||!meta.home_team||!meta.away_team)continue;
  const event={teamA:meta.home_team,teamB:meta.away_team,cat:meta.source_category,
   unclassified_sports:meta.unclassified_sports===true,
   eventInfo:{teamA:meta.home_team,teamB:meta.away_team,teamAFlag:meta.home_logo_url,teamBFlag:meta.away_logo_url,
    eventCat:meta.source_category,eventName:reviewedLeague(meta.league)||reviewedLeague(meta.source_category)||meta.league,startTime:meta.kickoff_at||meta.source_time,endTime:meta.end_at,
    sourceCivilDate:meta.source_civil_date,sourceTime:meta.source_time},
   resolved_streams:(entry.streams||[]).map(line=>({...line,title:line.label}))};
  rows.push(...parseRepositoryMatches(JSON.stringify([event]),{repository,source_file:entry.source_file}));
 }
 return {revision:await sourceHash('hub-repository-v2:'+revision),unchanged:false,
  entries:await mergeRepositoryMatches(mergeVerifiedAliases(rows),{now}),complete,missingRepositories:[...missing]};
}
