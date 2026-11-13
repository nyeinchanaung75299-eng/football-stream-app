// Pick Big Matches deliberately allows only the two maintained fixture feeds.
// Repository Match links are published by the dedicated repository RPC.
const pickBigMatchProviders = <String, String>{
  'cola': 'ColaTV',
  'repository': 'Repository Match',
};

bool isPickBigMatchProvider(String provider) =>
    pickBigMatchProviders.containsKey(provider);
