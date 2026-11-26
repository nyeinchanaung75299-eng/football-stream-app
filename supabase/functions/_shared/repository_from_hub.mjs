// The production Repository/Live 2 pipeline consumes the last committed Hub
// snapshot. It performs no GitHub requests and cannot modify operator lines.
import {parseRepositoryMatches,mergeRepositoryMatches,preserveRepositoryMatchLines} from './repository_matches.mjs';
import {sourceHash} from './darkbyte_catalog.mjs';
import {REPOSITORY_TREE_SOURCES} from './repository_trees.mjs';
const leagues = new Map([
 ['epl', 'Premier League'], ['premier league', 'Premier League'],
 ['laliga', 'LaLiga'], ['la liga', 'LaLiga'],
 ['laliga 2', 'LaLiga 2'], ['la liga 2', 'LaLiga 2'],
 ['ligue 1', 'Ligue 1'], ['serie a', 'Serie A'], ['bundesliga', 'Bundesliga'],
 ["ucl","UEFA Champions League"],
 ["uefa champions league","UEFA Champions League"],
 ["uel","UEFA Europa League"],
 ["uefa europa league","UEFA Europa League"],
 ["uecl","UEFA Conference League"],
 ["uefa conference league","UEFA Conference League"],
 ["uefa europa conference league","UEFA Conference League"],
 ["uefa youth","UEFA Youth League"],
 ["uefa youth league","UEFA Youth League"],
 ["afc champions league two","AFC Champions League Two"],
 ["afc champions league 2","AFC Champions League Two"],
 ["afc champions league elite","AFC Champions League Elite"],
]);
function reviewedLeague(value) {
 return leagues.get(String(value || '').toLowerCase().replace(/[^a-z0-9 ]/g, '').trim());
}
function badgeId(value) {
 return /^https:\/\/img\.sofascore\.com\/api\/v1\/team\/(\d+)\/image(?:[?].*)?$/.exec(value || '')?.[1];
}
function fixtureLeague(value) {
 const reviewed=reviewedLeague(value);
 if(reviewed)return reviewed;
 // New named competitions may be corroborated without a hard-coded alias,
 // but generic labels and match titles are never competition evidence.
 const text=String(value||'').normalize('NFKC').trim().toLowerCase().replace(/\s+/g,' ');
 if(!text||/\b(?:vs\.?|versus)\b/.test(text)||!/\b(?:league|cup|championship|division|premiership|liga|ligue)\b/.test(text))return null;
 if(/^(?:league|cup|championship|division|champions league|europa league|live league)$/.test(text))return null;
 return text;
}
function teamClass(value) {
 const name=String(value||'').normalize('NFKC').toLowerCase();
 const age=name.match(/\bu[\s-]?(\d{1,2})\b/);
 const women=/\b(?:women(?:'s)?|ladies|female|frauen|femenino|femenina|femminile)\b/.test(name);
 const reserve=/(?:\b(?:reserves?|reserve team)|\s(?:ii|b))\s*$/.test(name);
 return [age?.[1]||'',women?'women':'',reserve?'reserve':''].join(':');
}
function fixtureEvidence(row,kickoff=row.kickoff_at) {
 const home=badgeId(row.home_logo_url),away=badgeId(row.away_logo_url);
 const league=fixtureLeague(row.league);
 const when=Date.parse(kickoff||'');
 return home&&away&&home!==away&&league&&Number.isFinite(when)
  ? JSON.stringify([league,home,away,new Date(when).toISOString(),row.competition_tag||'',teamClass(row.home_team),teamClass(row.away_team)])
  : null;
}
// Only corroborate the literal clock and date against an independently
// dated source with the same competition and ordered team IDs.
function reportedWallClock(value) {
 const parts=/^(\d{2})\/(\d{2})\/(\d{4}) (\d{2}:\d{2}:\d{2})$/.exec(value || '');
 return parts ? `${parts[3]}-${parts[2]}-${parts[1]}T${parts[4]}.000Z` : null;
}
// A generic sport label is not a second competition. Corroborate it only
// against one uniquely identified named competition with exact fixture IDs,
// kickoff and team class. Never infer a league from an ambiguous named pair.
function fixtureIdentity(row) {
 const home=badgeId(row.home_logo_url),away=badgeId(row.away_logo_url);
 const when=Date.parse(row.kickoff_at||'');
 if(!home||!away||home===away||!Number.isFinite(when))return null;
 return JSON.stringify([home,away,new Date(when).toISOString(),row.competition_tag||'',teamClass(row.home_team),teamClass(row.away_team)]);
}
function genericSportLeague(value) {
 return /^(?:football|soccer|live sports|live events)$/i.test(String(value||'').trim());
}
function corroborateGenericLeagues(rows) {
 const byFixture=new Map();
 for(const row of rows){
  const identity=fixtureIdentity(row),league=fixtureLeague(row.league);
  if(!identity||!league)continue;
  const named=byFixture.get(identity)||new Map();
  named.set(league,reviewedLeague(row.league)||row.league);
  byFixture.set(identity,named);
 }
 for(const row of rows){
  if(!genericSportLeague(row.league))continue;
  const identity=fixtureIdentity(row);
  const named=identity&&byFixture.get(identity);
  if(named?.size===1)row.league=named.values().next().value;
 }
 return rows;
}
function mergeVerifiedAliases(rows) {
 corroborateGenericLeagues(rows);
 const groups = new Map();
 for (const row of rows) {
  const evidence = fixtureEvidence(row);
  if (!evidence) continue;
  const group = groups.get(evidence) || [];
  group.push(row);
  groups.set(evidence, group);
 }
 for (const row of rows) {
  if (row.kickoff_at) continue;
  const evidence=fixtureEvidence(row,reportedWallClock(row.source_time));
  const confirmed=groups.get(evidence);
  if (!confirmed?.some(peer=>peer.repository!==row.repository)) continue;
  row.kickoff_at=confirmed[0].kickoff_at;
  row.corroborated_clock=true;
  confirmed.push(row);
 }
 for (const group of groups.values()) {
  // Dated rows may be duplicate provider exports from the same repository.
  // Both ordered team IDs, named competition and exact kickoff must agree.
  if (group.length < 2) continue;
  const canonical = [...group].sort((a, b) =>
   Number(Boolean(a.corroborated_clock))-Number(Boolean(b.corroborated_clock)) ||
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
export function reconcileUndatedRepositoryAliases(entries,previous) {
 const confirmed=new Map();
 for(const entry of entries){
  const evidence=fixtureEvidence(entry.event_meta || {});
  if(!evidence)continue;
  const candidates=confirmed.get(evidence) || [];
  candidates.push(entry.id);
  confirmed.set(evidence,candidates);
 }
 const byId=new Map(entries.map(entry=>[entry.id,entry]));
 const superseded=[];
 for(const old of previous){
  const meta=old.event_meta || {};
  if(meta.kickoff_at||byId.has(old.id))continue;
  const candidates=confirmed.get(fixtureEvidence(meta,reportedWallClock(meta.source_time)));
  if(candidates?.length!==1)continue;
  const candidate=byId.get(candidates[0]),origins=new Set(meta.repositories || []);
  if(!candidate.event_meta.repositories?.some(repo=>!origins.has(repo)))continue;
  const [merged]=preserveRepositoryMatchLines([candidate],[{...old,id:candidate.id}]);
  byId.set(candidate.id,merged);
  superseded.push(old.id);
 }
 return {entries:[...byId.values()],superseded};
}
export async function repositoryMatchesFromHub(entries,{revision='',missingRepositories=[],complete=true,now=Date.now()}={}){
 const missing=new Set(!complete&&!missingRepositories.length?REPOSITORY_TREE_SOURCES:missingRepositories),rows=[];
 for(const entry of entries){
  if(entry.kind!=='event')continue;
  const meta=entry.event_meta||{},repository=meta.source_repository;
  if(!REPOSITORY_TREE_SOURCES.includes(repository)||(missing.has(repository)&&meta.source_partial_fresh!==true)||!meta.home_team||!meta.away_team)continue;
  const event={teamA:meta.home_team,teamB:meta.away_team,cat:meta.source_category,
   unclassified_sports:meta.unclassified_sports===true,
   eventInfo:{teamA:meta.home_team,teamB:meta.away_team,teamAFlag:meta.home_logo_url,teamBFlag:meta.away_logo_url,
    eventCat:meta.source_category,eventName:reviewedLeague(meta.league)||reviewedLeague(meta.source_category)||meta.league,startTime:meta.kickoff_at||meta.source_time,endTime:meta.end_at,
    sourceCivilDate:meta.source_civil_date,sourceTime:meta.source_time},
   resolved_streams:(entry.streams||[]).map(line=>({...line,title:line.label}))};
  rows.push(...parseRepositoryMatches(JSON.stringify([event]),{repository,source_file:entry.source_file}));
 }
 return {revision:await sourceHash('hub-repository-v5:'+revision),unchanged:false,
  entries:await mergeRepositoryMatches(mergeVerifiedAliases(rows),{now}),complete,missingRepositories:[...missing]};
}
