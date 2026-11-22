const pickBigMatchProviders = <String, String>{
  'cola': 'ColaTV',
  'repository': 'Repository Match',
  'combat': 'Combat Sports',
};

bool isPickBigMatchProvider(String provider) =>
    pickBigMatchProviders.containsKey(provider);
