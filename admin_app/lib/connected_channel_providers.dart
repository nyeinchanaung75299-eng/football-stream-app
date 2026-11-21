const connectedChannelProviders = <int, String>{
  1: 'Darkbyte Provider 1',
  2: 'Darkbyte Provider 2',
  3: 'Darkbyte Provider 3',
  4: 'Darkbyte Provider 4',
  5: 'Darkbyte Provider 5',
  6: 'Darkbyte Provider 6',
  9: 'SM IPTV',
  10: 'Allrounder Live',
  11: 'SM Sports Data',
  12: 'DudeTV',
};

String connectedChannelProviderName(Object? value) =>
    connectedChannelProviders[(value as num?)?.toInt()] ?? 'Provider $value';
