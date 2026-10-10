// Canonical Chinese aliases mirror the verified football_names.mjs source names.
// Display text never changes source IDs, room URLs, match time or import identity.
const _footballAliases = <String, String>{
  "欧冠杯": "UEFA Champions League",
  "欧冠": "UEFA Champions League",
  "欧罗巴杯": "UEFA Europa League",
  "欧联杯": "UEFA Europa League",
  "欧协联": "UEFA Conference League",
  "世俱杯": "FIFA Club World Cup",
  "英联杯": "EFL Cup",
  "英甲": "English League One",
  "英乙": "English League Two",
  "英议联": "English National League",
  "德丙": "3. Liga",
  "德地区": "German Regionalliga",
  "德青联": "German Youth League",
  "西乙": "Spanish Segunda Division",
  "西杯": "Copa del Rey",
  "意乙": "Italian Serie B",
  "意杯": "Coppa Italia",
  "法乙": "French Ligue 2",
  "法丙": "French National",
  "葡超": "Portuguese Primeira Liga",
  "葡甲": "Portuguese Liga Portugal 2",
  "荷甲": "Netherlands Eredivisie",
  "荷乙": "Netherlands Eerste Divisie",
  "荷丙": "Netherlands Tweede Divisie",
  "比甲": "Belgian Pro League",
  "苏超": "Scottish Premiership",
  "苏冠": "Scottish Championship",
  "瑞士超": "Swiss Super League",
  "瑞典超": "Swedish Allsvenskan",
  "挪超": "Norwegian Eliteserien",
  "丹麦超": "Danish Superliga",
  "丹麦甲": "Danish 1st Division",
  "奥甲": "Austrian Bundesliga",
  "土超": "Turkish Super Lig",
  "土甲": "Turkish 1. Lig",
  "俄超": "Russian Premier League",
  "乌克超": "Ukrainian Premier League",
  "波兰甲": "Polish Ekstraklasa",
  "捷甲": "Czech First League",
  "希腊超": "Greek Super League",
  "塞尔超": "Serbian SuperLiga",
  "克亚甲": "Croatian First Football League",
  "罗甲": "Romanian Liga I",
  "保甲": "Bulgarian First League",
  "匈甲": "Hungarian NB I",
  "立陶甲": "Lithuanian A Lyga",
  "格鲁甲": "Georgian Erovnuli Liga",
  "爱沙甲": "Estonian Meistriliiga",
  "斯伐超": "Slovak First League",
  "冰岛超": "Icelandic Besta deild",
  "以超": "Israeli Premier League",
  "沙特联": "Saudi Pro League",
  "卡塔尔联": "Qatar Stars League",
  "阿联酋超": "UAE Pro League",
  "伊朗超": "Iranian Persian Gulf Pro League",
  "澳超": "Australian A-League",
  "印尼甲": "Indonesia Liga 1",
  "泰超": "Thai League 1",
  "泰甲": "Thai League 2",
  "新加坡联": "Singapore Premier League",
  "印度超": "Indian Super League",
  "巴西甲": "Brazil Serie A",
  "阿甲": "Argentina Primera Division",
  "墨西超": "Mexico Liga MX",
  "美乙": "USL Championship",
  "中乙": "China League Two",
  "中女超": "Chinese Women's Super League",
  "中U21": "Chinese U21 League",
  "日职丙": "Japanese J3 League",
  "韩K2联": "Korean K League 2",
  "韩K3联": "Korean K3 League",
  "帕德博恩": "SC Paderborn 07",
  "斯图加特": "VfB Stuttgart",
  "柏林联合": "1. FC Union Berlin",
  "埃弗斯堡": "SV 07 Elversberg",
  "奥格斯堡": "FC Augsburg",
  "霍芬海姆": "TSG Hoffenheim",
  "汉堡": "Hamburger SV",
  "美因茨": "Mainz 05",
  "勒沃库森": "Bayer Leverkusen",
  "多特蒙德": "Borussia Dortmund",
  "法兰克福": "Eintracht Frankfurt",
  "门兴格拉德巴赫": "Borussia Monchengladbach",
  "弗赖堡": "SC Freiburg",
  "沃尔夫斯堡": "VfL Wolfsburg",
  "云达不莱梅": "Werder Bremen",
  "海登海姆": "1. FC Heidenheim",
  "圣保利": "FC St. Pauli",
  "科隆": "FC Cologne",
  "RB莱比锡": "RB Leipzig",
  "莱比锡": "RB Leipzig",
  "沙尔克04": "Schalke 04",
  "汉诺威96": "Hannover 96",
  "杜塞尔多夫": "Fortuna Dusseldorf",
  "卡尔斯鲁厄": "Karlsruher SC",
  "纽伦堡": "1. FC Nuremberg",
  "凯泽斯劳滕": "1. FC Kaiserslautern",
  "达姆施塔特": "SV Darmstadt 98",
  "柏林赫塔": "Hertha BSC",
  "巴列卡诺": "Rayo Vallecano",
  "毕尔巴鄂竞技": "Athletic Bilbao",
  "阿拉维斯": "Deportivo Alaves",
  "里尔": "Lille",
  "勒阿弗尔": "Le Havre",
  "国际米兰": "Inter Milan",
  "帕尔马": "Parma",
  "塞维利亚": "Sevilla",
  "皇家贝蒂斯": "Real Betis",
  "皇家社会": "Real Sociedad",
  "塞尔塔": "Celta Vigo",
  "奥萨苏纳": "Osasuna",
  "赫塔菲": "Getafe",
  "赫罗纳": "Girona",
  "西班牙人": "Espanyol",
  "瓦伦西亚": "Valencia",
  "马洛卡": "Mallorca",
  "莱万特": "Levante",
  "埃尔切": "Elche",
  "尤文图斯": "Juventus",
  "AC米兰": "AC Milan",
  "那不勒斯": "Napoli",
  "罗马": "AS Roma",
  "拉齐奥": "Lazio",
  "亚特兰大": "Atalanta",
  "佛罗伦萨": "Fiorentina",
  "博洛尼亚": "Bologna",
  "都灵": "Torino",
  "热那亚": "Genoa",
  "乌迪内斯": "Udinese",
  "萨索洛": "Sassuolo",
  "莱切": "Lecce",
  "科莫": "Como",
  "维罗纳": "Hellas Verona",
  "马赛": "Marseille",
  "里昂": "Lyon",
  "摩纳哥": "Monaco",
  "尼斯": "Nice",
  "雷恩": "Rennes",
  "斯特拉斯堡": "Strasbourg",
  "南特": "Nantes",
  "朗斯": "Lens",
  "布雷斯特": "Brest",
  "图卢兹": "Toulouse",
  "梅斯": "Metz",
  "洛里昂": "Lorient",
  "埃弗顿": "Everton",
  "西汉姆联": "West Ham United",
  "纽卡斯尔联": "Newcastle United",
  "水晶宫": "Crystal Palace",
  "狼队": "Wolverhampton Wanderers",
  "南安普顿": "Southampton",
  "莱斯特城": "Leicester City",
  "伯恩利": "Burnley",
  "谢菲尔德联": "Sheffield United",
  "考文垂": "Coventry City",
  "西布罗姆维奇": "West Bromwich Albion",
  "伯明翰": "Birmingham City",
  "诺维奇": "Norwich City",
  "斯旺西": "Swansea City",
  "查尔顿": "Charlton Athletic",
  "布里斯托城": "Bristol City",
  "牛津联队": "Oxford United",
  "普利茅斯": "Plymouth Argyle",
  "诺茨郡": "Notts County",
  "AFC温布尔登": "AFC Wimbledon",
  "阿贾克斯": "Ajax",
  "埃因霍温": "PSV Eindhoven",
  "费耶诺德": "Feyenoord",
  "特温特": "FC Twente",
  "本菲卡": "Benfica",
  "波尔图": "FC Porto",
  "葡萄牙体育": "Sporting CP",
  "加拉塔萨雷": "Galatasaray",
  "费内巴切": "Fenerbahce",
  "贝西克塔斯": "Besiktas",
  "凯尔特人": "Celtic",
  "格拉斯哥流浪者": "Rangers",
  "欧国联": "UEFA Nations League",
  "中北美国联": "CONCACAF Nations League",
  "女欧U19": "UEFA Women's U19",
  "女欧U17": "UEFA Women's U17",
  "日皇杯": "Emperor's Cup",
  "美职业": "MLS",
  "非洲杯": "Africa Cup of Nations",
  "英足总杯": "FA Cup",
  "英锦赛": "EFL Trophy",
  "巴西乙": "Brazil Serie B",
  "智利杯": "Chile Cup",
  "英超": "English Premier League",
  "英冠": "Championship",
  "德甲": "Bundesliga",
  "德乙": "2. Bundesliga",
  "西甲": "Spanish La Liga",
  "意甲": "Italian Serie A",
  "法甲": "French Ligue 1",
  "中超": "Chinese Super League",
  "中甲": "China League One",
  "日职联": "Japanese J1 League",
  "日职乙": "Japanese J2 League",
  "韩K联": "Korean K League 1",
  "国际友谊": "International Friendly",
  "阿森纳": "Arsenal",
  "切尔西": "Chelsea",
  "伯恩茅斯": "Bournemouth",
  "热刺": "Tottenham Hotspur",
  "托特纳姆热刺": "Tottenham Hotspur",
  "曼彻斯特联": "Manchester United",
  "曼联": "Manchester United",
  "曼彻斯特城": "Manchester City",
  "曼城": "Manchester City",
  "利物浦": "Liverpool",
  "富勒姆": "Fulham",
  "利兹联": "Leeds United",
  "伊普斯维奇": "Ipswich Town",
  "桑德兰": "Sunderland",
  "阿斯顿维拉": "Aston Villa",
  "布伦特福德": "Brentford",
  "诺丁汉森林": "Nottingham Forest",
  "布莱顿": "Brighton & Hove Albion",
  "皇家马德里": "Real Madrid",
  "马德里竞技": "Atletico Madrid",
  "巴塞罗那": "Barcelona",
  "比利亚雷亚尔": "Villarreal",
  "拜仁慕尼黑": "Bayern Munich",
  "巴黎圣日耳曼": "Paris Saint-Germain",
  "北爱尔兰": "Northern Ireland",
  "格鲁吉亚": "Georgia",
  "意大利": "Italy",
  "土耳其": "Turkey",
  "法国": "France",
  "罗马尼亚": "Romania",
  "瑞典": "Sweden",
  "乌克兰": "Ukraine",
  "匈牙利": "Hungary",
  "黑山": "Montenegro",
  "亚美尼亚": "Armenia",
  "德国": "Germany",
  "西班牙": "Spain",
  "葡萄牙": "Portugal",
  "荷兰": "Netherlands",
  "克罗地亚": "Croatia",
  "波兰": "Poland",
  "丹麦": "Denmark",
  "挪威": "Norway",
  "芬兰": "Finland",
  "瑞士": "Switzerland",
  "奥地利": "Austria",
  "希腊": "Greece",
  "捷克": "Czechia",
  "塞尔维亚": "Serbia",
  "苏格兰": "Scotland",
  "爱尔兰": "Ireland",
  "中国台北": "Chinese Taipei",
  "北马其顿": "North Macedonia",
  "斯洛文尼亚": "Slovenia",
  "卢森堡": "Luxembourg",
  "保加利亚": "Bulgaria",
  "摩尔多瓦": "Moldova",
  "斯洛伐克": "Slovakia",
  "爱沙尼亚": "Estonia",
  "冰岛": "Iceland",
  "白俄罗斯": "Belarus",
  "白Russia": "Belarus",
  "阿尔巴尼亚": "Albania",
  "圣马力诺": "San Marino",
  "安哥拉": "Angola",
  "马拉维": "Malawi",
  "圣文森特和格林纳丁斯": "Saint Vincent and the Grenadines",
  "荷属圣马丁岛": "Sint Maarten",
  "安提瓜和巴布达": "Antigua and Barbuda",
  "阿鲁巴": "Aruba",
  "阿根廷": "Argentina",
  "贝宁": "Benin",
  "哥伦比亚": "Colombia",
  "秘鲁": "Peru",
  "美国": "USA",
  "加拿大": "Canada",
  "法属圭亚那": "French Guiana",
  "伯利兹": "Belize",
  "墨西哥": "Mexico",
  "智利": "Chile",
  "印度": "India",
  "中国": "China",
  "波黑": "Bosnia and Herzegovina",
  "乌兹别克斯坦": "Uzbekistan",
  "乌兹别克": "Uzbekistan",
  "菲律宾": "Philippines",
  "哈萨克斯坦": "Kazakhstan",
  "俄罗斯": "Russia",
  "英格兰": "England",
  "比利时": "Belgium",
  "柬埔寨": "Cambodia",
  "马来西亚": "Malaysia",
  "印度尼西亚": "Indonesia",
  "新西兰": "New Zealand",
  "澳大利亚": "Australia",
  "韩国": "South Korea",
  "朝鲜": "North Korea",
  "越南杯": "Vietnam Cup",
  "越南": "Vietnam",
  "泰国": "Thailand",
  "日本": "Japan",
  "缅甸": "Myanmar",
  "老挝": "Laos",
  "新加坡": "Singapore",
  "伊朗": "Iran",
  "伊拉克": "Iraq",
  "沙特": "Saudi Arabia",
  "卡塔尔": "Qatar",
  "阿联酋": "UAE",
  "中亚女": "Central Asia Women ",
  "女足": " Women ",
  "后备队": " Reserves",
  "足球": "Football",
};

final _nonLatin = RegExp(
  r'[^\x20-\x7e\u00a0-\u024f\u0300-\u036f\u1e00-\u1eff\u2000-\u206f]',
);
final _aliasPattern = RegExp(
  (_footballAliases.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
      .map(RegExp.escape)
      .join('|'),
);

/// Applies known translations only. Unknown manual names remain untouched.
String englishFootballName(Object? value, {String kind = 'team'}) {
  final original = _nameCandidates(value).firstOrNull ?? '';
  final translated = original
      .replaceAllMapped(_aliasPattern, (m) => _footballAliases[m[0]]!)
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll(RegExp(r'女(?=U\d|$)'), ' Women ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])(?=U\d{1,2}\b)'), (m) => '${m[1]} ')
      .trim();
  return _nonLatin.hasMatch(translated) ? original : translated;
}

String englishKnownFootballName(String raw, {String kind = 'team'}) =>
    englishFootballName(raw, kind: kind);

Iterable<String> _nameCandidates(Object? value) sync* {
  if (value is String && value.trim().isNotEmpty) {
    yield value.trim();
  } else if (value is Map) {
    for (final field in const [
      'name_en',
      'en_name',
      'english_name',
      'nameEn',
      'englishName',
      'en',
      'name',
    ]) {
      yield* _nameCandidates(value[field]);
    }
  }
}

String _englishCandidate(
  Iterable<Object?> values,
  String fallback, {
  String kind = 'team',
  bool translateFootball = true,
}) {
  for (final value in values) {
    for (final candidate in _nameCandidates(value)) {
      final translated = translateFootball
          ? englishFootballName(candidate, kind: kind)
          : candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (translated.isNotEmpty && !_nonLatin.hasMatch(translated)) {
        return translated;
      }
    }
  }
  return fallback;
}

String _identityToken(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return '';
  if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(raw)) return raw;
  // A non-Latin provider ID still gets a stable display reference.
  var hash = 2166136261;
  for (final unit in raw.codeUnits) {
    hash ^= unit;
    // Shift/add keeps the low 32 bits exact in both Dart VM and JavaScript.
    hash =
        (hash +
            (hash << 1) +
            (hash << 4) +
            (hash << 7) +
            (hash << 8) +
            (hash << 24)) &
        0xffffffff;
  }
  return hash.toRadixString(16);
}

String _fallback(String label, Object? id) {
  final token = _identityToken(id);
  return token.isEmpty ? label : '$label ($token)';
}

/// Also normalizes old API, mirror and on-device cache rows for YYZB.
Map<String, dynamic> englishSourceMatch(
  Map<String, dynamic> row,
  String source,
) {
  if (source.toLowerCase() != 'yyzb') return row;
  final id = row['source_id'] ?? row['schedule_id'] ?? row['id'];
  final result = Map<String, dynamic>.from(row);
  result['original_home_team'] ??= row['home_team'];
  result['original_away_team'] ??= row['away_team'];
  result['original_league'] ??= row['league'];
  result['home_team'] = _englishCandidate([
    row['home_team_en'],
    row['homeNameEn'],
    row['hostNameEn'],
    row['homeTeamNameEn'],
    row['home_team'],
    row['homeName'],
    row['hostName'],
  ], _fallback('Home team', id));
  result['away_team'] = _englishCandidate([
    row['away_team_en'],
    row['awayNameEn'],
    row['guestNameEn'],
    row['awayTeamNameEn'],
    row['away_team'],
    row['awayName'],
    row['guestName'],
  ], _fallback('Away team', id));
  result['league'] = _englishCandidate(
    [
      row['league_en'],
      row['leagueNameEn'],
      row['subCateNameEn'],
      row['competitionNameEn'],
      row['league'],
      row['leagueName'],
      row['subCateName'],
    ],
    _fallback(
      'Football league',
      row['league_id'] ?? row['subCateId'] ?? row['competition_id'],
    ),
    kind: 'league',
  );
  final rawAnchors = row['anchors'];
  if (rawAnchors is List) {
    result['anchors'] = rawAnchors.asMap().entries.map((entry) {
      if (entry.value is! Map) return entry.value;
      final anchor = Map<String, dynamic>.from(entry.value as Map);
      anchor['original_nick_name'] ??=
          anchor['nick_name'] ?? anchor['nickName'] ?? anchor['name'];
      anchor['nick_name'] = englishSourceAnchorName(anchor, entry.key);
      return anchor;
    }).toList();
  }
  return result;
}

String _audioLanguage(String name) {
  if (RegExp(
    r'粤语|粵語|粤|粵|廣東話|广东话|\bCantonese\b',
    caseSensitive: false,
  ).hasMatch(name)) {
    return 'Cantonese';
  }
  if (RegExp(
    r'国语|國語|普通话|普通話|\bMandarin\b',
    caseSensitive: false,
  ).hasMatch(name)) {
    return 'Mandarin';
  }
  return '';
}

String englishSourceAnchorName(Map<String, dynamic> anchor, int index) {
  final raw = [
    anchor['original_nick_name'],
    anchor['nick_name'],
    anchor['nickName'],
    anchor['name'],
  ].expand(_nameCandidates).join(' ');
  final preferred = _englishCandidate(
    [
      anchor['nick_name_en'],
      anchor['nickNameEn'],
      anchor['name_en'],
      anchor['en_name'],
      anchor['english_name'],
      anchor['nick_name'],
      anchor['nickName'],
      anchor['name'],
    ],
    'Streamer ${index + 1}',
    translateFootball: false,
  );
  final language = _audioLanguage(raw);
  return language.isEmpty ||
          preferred.toLowerCase().contains(language.toLowerCase())
      ? preferred
      : '$preferred ($language)';
}

/// Renames non-Latin commentator fragments in YYZB labels for presentation.
/// Resolution, protocol and audio language remain visible; stored labels stay intact.
String englishStreamLabel(String raw, {int index = 0}) {
  if (!_nonLatin.hasMatch(raw)) return raw;
  final parts = raw.split(RegExp(r'\s*[•|]\s*'));
  final result = <String>[];
  for (final part in parts) {
    if (!_nonLatin.hasMatch(part)) {
      if (part.trim().isNotEmpty) result.add(part.trim());
      continue;
    }
    final language = _audioLanguage(part);
    final name =
        'Streamer ${index + 1}${language.isEmpty ? '' : ' ($language)'}';
    if (!result.contains(name)) result.add(name);
    final metadata = RegExp(
      r'\b(?:\d{3,4}p|FHD|UHD|HD|SD|4K|HLS|DASH|MPD|M3U8|FLV|MP4|AUTO|LIVE|READY)\b',
      caseSensitive: false,
    ).allMatches(part).map((m) => m[0]!).toList();
    if (metadata.isNotEmpty) result.add(metadata.join(' '));
  }
  return result.join(' • ');
}
