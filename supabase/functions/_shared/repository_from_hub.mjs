// The production Repository/Live 2 pipeline consumes the last committed Hub
// snapshot. It performs no GitHub requests and cannot modify operator lines.
import {parseRepositoryMatches,mergeRepositoryMatches} from './repository_matches.mjs';
import {sourceHash} from './darkbyte_catalog.mjs';
import {REPOSITORY_TREE_SOURCES} from './repository_trees.mjs';
export async function repositoryMatchesFromHub(entries,{revision='',missingRepositories=[],complete=true,now=Date.now()}={}){
 const missing=new Set(!complete&&!missingRepositories.length?REPOSITORY_TREE_SOURCES:missingRepositories),rows=[];
 for(const entry of entries){
  if(entry.kind!=='event')continue;
  const meta=entry.event_meta||{},repository=meta.source_repository;
  if(!repository||missing.has(repository)||!meta.home_team||!meta.away_team)continue;
  const event={teamA:meta.home_team,teamB:meta.away_team,cat:meta.source_category,
   unclassified_sports:meta.unclassified_sports===true,
   eventInfo:{teamA:meta.home_team,teamB:meta.away_team,teamAFlag:meta.home_logo_url,teamBFlag:meta.away_logo_url,
    eventCat:meta.source_category,eventName:meta.league,startTime:meta.kickoff_at||meta.source_time,endTime:meta.end_at,
    sourceCivilDate:meta.source_civil_date,sourceTime:meta.source_time},
   resolved_streams:(entry.streams||[]).map(line=>({...line,title:line.label}))};
  rows.push(...parseRepositoryMatches(JSON.stringify([event]),{repository,source_file:entry.source_file}));
 }
 return {revision:await sourceHash('hub-repository-v1:'+revision),unchanged:false,
  entries:await mergeRepositoryMatches(rows,{now}),complete,missingRepositories:[...missing]};
}
