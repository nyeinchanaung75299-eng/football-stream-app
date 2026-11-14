import {createViewerNetworkApi} from '../_shared/viewer_network_api.mjs';
// This is the existing client publishable key, not a service credential.
const publicKey = Deno.env.get('VIEWER_PUBLIC_API_KEY')?.trim() ||
  'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';
Deno.serve(createViewerNetworkApi({apiKey: publicKey}));
