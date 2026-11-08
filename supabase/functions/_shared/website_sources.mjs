import {arenaMatches,arenaStreams} from './arena_source.mjs';

export async function websiteMatches(source,{fetcher=fetch,now=Date.now(),date}={}){
 if(source==='arena')return arenaMatches({fetcher,now,date});
 throw Error('Unsupported website source');
}
export async function websiteStreams(source,body,{fetcher=fetch}={}){
 if(source==='arena')return arenaStreams(body,{fetcher});
 throw Error('Unsupported website source');
}
