// Provider restriction applies to Pick Big Matches only.
// The Stream Sources screen retains every separately configured provider.
const pickBigMatchProviders = <String, String>{
  'cola': 'ColaTV',
  'crichd': 'CricHD',
  'score088': 'Score088TV',
};

bool isPickBigMatchProvider(String provider) =>
    pickBigMatchProviders.containsKey(provider);
