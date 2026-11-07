// Produce private, replayable RPC batches after audit_repository_mpds.mjs.
// No credentials or source URLs are printed or checked into the repository.
import {readFileSync,writeFileSync} from 'node:fs';
import {mpdIdentity} from '../supabase/functions/_shared/repository_mpd.mjs';
const folder=process.argv[2];if(!folder)throw new Error('Private audit directory required');
const rows=JSON.parse(readFileSync(folder+'/audited-private.json'));
const database=JSON.parse(readFileSync(folder+'/database-private.json'));
const existing=new Set(database.lines.map(l=>mpdIdentity(l.stream_url)));
const fresh=rows.filter(r=>!r.existing_line_id&&!existing.has(mpdIdentity(r.stream_url)));
const fixes=rows.filter(r=>r.existing_line_id).map(r=>{
 const matches=rows.filter(x=>x.key_data&&r.manifest_kids?.includes(x.key_id.toLowerCase().replace(/-/g,'')));
 const pairs=[...new Set(matches.map(x=>x.key_id+':'+x.key_data))];
 return {...r,...(pairs.length===1?{key_id:matches[0].key_id,key_data:matches[0].key_data,configuration_status:'configured'}:{})};
});
writeFileSync(folder+'/keyless-repairs-private.json',JSON.stringify(fixes),{mode:0o600});
for(let offset=0;offset<fresh.length;offset+=50)writeFileSync(folder+'/import-batch-'+offset+'.json',JSON.stringify(fresh.slice(offset,offset+50)),{mode:0o600});
console.log(JSON.stringify({raw:rows.filter(r=>!r.existing_line_id).length,added_lines:fresh.length,skipped_existing:rows.length-fixes.length-fresh.length,
 existing_keyless_repairable:fixes.filter(r=>r.key_data).length,existing_keyless_needs_configuration:fixes.filter(r=>!r.key_data).length,
 new_configuration_states:fresh.reduce((a,r)=>(a[r.configuration_status]=(a[r.configuration_status]||0)+1,a),{}),
 actual_mpd_manifests:fresh.filter(r=>['clear','encrypted'].includes(r.manifest_status)).length}));
