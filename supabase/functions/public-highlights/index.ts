import {publicHighlightsRequest} from '../_shared/public_highlights.mjs';
Deno.serve((request:Request)=>publicHighlightsRequest(request));
