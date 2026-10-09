// Source feeds mix English, Vietnamese and Chinese labels. Normalize names at
// ingestion so Admin, Viewer and the VPN-off mirrors use the same display text.
// Unknown names stay readable; never erase them or guess a different club.
const latinText = value => String(value ?? '').normalize('NFD')
  .replace(/\p{M}+/gu, '').replace(/đ/g, 'd').replace(/Đ/g, 'D')
  .replace(/\s+/g, ' ').trim();
const key = value => latinText(value).toLowerCase();

const leagueAliases = new Map([
  ['Giải bóng đá Ngoại hạng Anh', 'English Premier League'],
  ['Giải Ngoại hạng Anh', 'English Premier League'],
  ['Giải bóng đá vô địch quốc gia Đức', 'Bundesliga'],
  ['Giải bóng đá Hạng hai Đức', '2. Bundesliga'],
  ['Giải bóng đá Serie A Italia', 'Italian Serie A'],
  ['Giải bóng đá Serie B Italia', 'Italian Serie B'],
  ['Giải Bóng đá Vô địch Quốc gia Tây Ban Nha', 'Spanish La Liga'],
  // Earlier normalization translated the country but left the league prefix.
  ['Giải Bóng đá Vô địch Quốc gia Spain', 'Spanish La Liga'],
  ['Giải Bóng đá Vô địch Quốc gia Pháp', 'French Ligue 1'],
  ['Giải Ngoại hạng Thổ Nhĩ Kỳ', 'Turkish Super Lig'],
  ['Giải Bóng đá Ngoại hạng Nga', 'Russian Premier League'],
  ['Giải Bóng đá Vô địch Quốc gia Bồ Đào Nha', 'Portuguese Primeira Liga'],
  ['Giải Bóng đá Vô địch Quốc gia Hà Lan', 'Netherlands Eredivisie'],
  ['Giải Bóng đá Vô địch Quốc gia Argentina', 'Argentina Primera Division'],
  ['Giải bóng đá Hạng nhất Brasil', 'Brazil Serie A'],
  ['Giải bóng đá Hạng nhì Brasil', 'Brazil Serie B'],
  ['Giải bóng đá Hạng nhì Colombia', 'Colombia Second Division'],
  ['Giải Bóng đá Vô địch Quốc gia Phần Lan', 'Finland Veikkausliiga'],
  ['Giải vô địch quốc gia Qatar', 'Qatar Stars League'],
  ['Giải vô địch quốc gia Việt Nam', 'Vietnam V.League 1'],
  ['Giải Vô địch quốc gia Ả-rập Xê-út', 'Saudi Pro League'],
  ['Giải Vô địch Bóng đá Quốc gia Mexico', 'Mexico Liga MX'],
  ['Giải K1 Hàn Quốc', 'Korean K League 1'],
  ['Giải K2 Hàn Quốc', 'Korean K League 2'],
  ['Giải vô địch quốc gia Nhật Bản', 'Japanese J1 League'],
  ['Giải bóng đá hạng nhì Nhật Bản', 'Japanese J2 League'],
  ['Giải bóng đá Liga 1 Indonesia', 'Indonesia Liga 1'],
  ['Giải bóng đá ngoại hạng Trung Quốc', 'Chinese Super League'],
  ['Giải bóng đá Hạng nhất Trung Quốc', 'China League One'],
  ['Giải bóng đá vô địch quốc gia Scotland', 'Scottish Premiership'],
  ['Cúp bóng đá của Hiệp hội Bóng đá Úc', 'Australia Cup'],
  ['Cúp Quốc gia', 'Vietnam National Cup'],
  ['Cúp Liên đoàn Bóng đá Ai Cập', 'Egypt League Cup'],
  ['Cúp Liên đoàn Bolivia', 'Bolivia League Cup'],
  ['Cúp liên đoàn UAE', 'UAE League Cup'],
  ['Cúp Chile', 'Chile Cup'],
  ['Giao hữu Quốc tế', 'International Friendly'],
  ['Giải vô địch bóng đá các quốc gia châu Âu', 'UEFA Nations League'],
].map(([from, to]) => [key(from), to]));

const teamAliases = new Map([
  ['Hàn Quốc', 'South Korea'], ['Trung Quốc', 'China'],
  ['Cộng hòa Tajikistan', 'Tajikistan'], ['Quần đảo Faroe', 'Faroe Islands'],
  ['Ấn Độ', 'India'], ['Bắc Macedonia', 'North Macedonia'],
  ['Cộng hòa Séc', 'Czechia'], ['Tây Ban Nha', 'Spain'],
  ['Thụy Sĩ', 'Switzerland'], ['Chilê', 'Chile'], ['Mỹ', 'USA'],
  ['Anh', 'England'], ['Đức', 'Germany'], ['Pháp', 'France'],
  ['Bồ Đào Nha', 'Portugal'], ['Hà Lan', 'Netherlands'],
  ['Đại học Kyoto Sangyo', 'Kyoto Sangyo University'],
  ['Thể Công - Viettel', 'The Cong - Viettel'],
  ['Hồng Lĩnh Hà Tĩnh', 'Hong Linh Ha Tinh'],
  ['Phong Phú Hà Nam', 'Phong Phu Ha Nam'], ['Hà Nội', 'Ha Noi'],
  ['Hoàng Anh Gia Lai', 'Hoang Anh Gia Lai'], ['SHB Đà Nẵng', 'SHB Da Nang'],
  ['Đông Á Thanh Hóa', 'Dong A Thanh Hoa'], ['Sông Lam Nghệ An', 'Song Lam Nghe An'],
  ['Thành phố Hồ Chí Minh', 'Ho Chi Minh City'],
  ['Diên Biên Hải Lan Giang', 'Yanbian Hailanjiang'],
  ['Zhixing Đại Liên', 'Dalian Zhixing'],
  ['Tongliangloong Trùng Khánh', 'Chongqing Tonglianglong'],
  ['Huế', 'Hue'], ['Bình Phước', 'Binh Phuoc'], ['Đồng Tháp', 'Dong Thap'],
].map(([from, to]) => [key(from), to]));

const chineseAliases = [
  ['欧国联', 'UEFA Nations League'], ['中北美国联', 'CONCACAF Nations League'],
  ['女欧U19', "UEFA Women's U19"], ['女欧U17', "UEFA Women's U17"],
  ['日皇杯', "Emperor's Cup"], ['美职业', 'MLS'],
  ['非洲杯', 'Africa Cup of Nations'], ['英足总杯', 'FA Cup'],
  ['英锦赛', 'EFL Trophy'], ['巴西乙', 'Brazil Serie B'], ['智利杯', 'Chile Cup'],
  ['英超', 'English Premier League'], ['英冠', 'Championship'],
  ['德甲', 'Bundesliga'], ['德乙', '2. Bundesliga'],
  ['西甲', 'Spanish La Liga'], ['意甲', 'Italian Serie A'], ['法甲', 'French Ligue 1'],
  ['中超', 'Chinese Super League'], ['中甲', 'China League One'],
  ['日职联', 'Japanese J1 League'], ['日职乙', 'Japanese J2 League'],
  ['韩K联', 'Korean K League 1'], ['国际友谊', 'International Friendly'],
  ['阿森纳', 'Arsenal'], ['切尔西', 'Chelsea'], ['伯恩茅斯', 'Bournemouth'],
  ['热刺', 'Tottenham Hotspur'], ['托特纳姆热刺', 'Tottenham Hotspur'],
  ['曼彻斯特联', 'Manchester United'], ['曼联', 'Manchester United'],
  ['曼彻斯特城', 'Manchester City'], ['曼城', 'Manchester City'],
  ['利物浦', 'Liverpool'], ['富勒姆', 'Fulham'], ['利兹联', 'Leeds United'],
  ['伊普斯维奇', 'Ipswich Town'], ['桑德兰', 'Sunderland'],
  ['阿斯顿维拉', 'Aston Villa'], ['布伦特福德', 'Brentford'],
  ['诺丁汉森林', 'Nottingham Forest'], ['布莱顿', 'Brighton & Hove Albion'],
  ['皇家马德里', 'Real Madrid'], ['马德里竞技', 'Atletico Madrid'],
  ['巴塞罗那', 'Barcelona'], ['比利亚雷亚尔', 'Villarreal'],
  ['拜仁慕尼黑', 'Bayern Munich'], ['巴黎圣日耳曼', 'Paris Saint-Germain'],
  ['北爱尔兰', 'Northern Ireland'], ['格鲁吉亚', 'Georgia'],
  ['意大利', 'Italy'], ['土耳其', 'Turkey'], ['法国', 'France'],
  ['罗马尼亚', 'Romania'], ['瑞典', 'Sweden'], ['乌克兰', 'Ukraine'],
  ['匈牙利', 'Hungary'], ['黑山', 'Montenegro'], ['亚美尼亚', 'Armenia'],
  ['德国', 'Germany'], ['西班牙', 'Spain'], ['葡萄牙', 'Portugal'],
  ['荷兰', 'Netherlands'], ['克罗地亚', 'Croatia'], ['波兰', 'Poland'],
  ['丹麦', 'Denmark'], ['挪威', 'Norway'], ['芬兰', 'Finland'],
  ['瑞士', 'Switzerland'], ['奥地利', 'Austria'], ['希腊', 'Greece'],
  ['捷克', 'Czechia'], ['塞尔维亚', 'Serbia'], ['苏格兰', 'Scotland'],
  ['爱尔兰', 'Ireland'], ['中国台北', 'Chinese Taipei'],
  ['北马其顿', 'North Macedonia'], ['斯洛文尼亚', 'Slovenia'],
  ['卢森堡', 'Luxembourg'], ['保加利亚', 'Bulgaria'], ['摩尔多瓦', 'Moldova'],
  ['斯洛伐克', 'Slovakia'], ['爱沙尼亚', 'Estonia'], ['冰岛', 'Iceland'],
  ['白俄罗斯', 'Belarus'], ['白Russia', 'Belarus'], ['阿尔巴尼亚', 'Albania'],
  ['圣马力诺', 'San Marino'], ['安哥拉', 'Angola'], ['马拉维', 'Malawi'],
  ['圣文森特和格林纳丁斯', 'Saint Vincent and the Grenadines'],
  ['荷属圣马丁岛', 'Sint Maarten'], ['安提瓜和巴布达', 'Antigua and Barbuda'],
  ['阿鲁巴', 'Aruba'], ['阿根廷', 'Argentina'], ['贝宁', 'Benin'],
  ['哥伦比亚', 'Colombia'], ['秘鲁', 'Peru'], ['美国', 'USA'],
  ['加拿大', 'Canada'], ['法属圭亚那', 'French Guiana'], ['伯利兹', 'Belize'],
  ['墨西哥', 'Mexico'], ['智利', 'Chile'], ['印度', 'India'], ['中国', 'China'],
  ['波黑', 'Bosnia and Herzegovina'], ['乌兹别克斯坦', 'Uzbekistan'],
  ['乌兹别克', 'Uzbekistan'], ['菲律宾', 'Philippines'],
  ['哈萨克斯坦', 'Kazakhstan'], ['俄罗斯', 'Russia'], ['英格兰', 'England'],
  ['比利时', 'Belgium'], ['柬埔寨', 'Cambodia'], ['马来西亚', 'Malaysia'],
  ['印度尼西亚', 'Indonesia'], ['新西兰', 'New Zealand'], ['澳大利亚', 'Australia'],
  ['韩国', 'South Korea'], ['朝鲜', 'North Korea'], ['越南杯', 'Vietnam Cup'],
  ['越南', 'Vietnam'], ['泰国', 'Thailand'], ['日本', 'Japan'],
  ['缅甸', 'Myanmar'], ['老挝', 'Laos'], ['新加坡', 'Singapore'],
  ['伊朗', 'Iran'], ['伊拉克', 'Iraq'], ['沙特', 'Saudi Arabia'],
  ['卡塔尔', 'Qatar'], ['阿联酋', 'UAE'], ['中亚女', 'Central Asia Women '],
  ['女足', ' Women '], ['后备队', ' Reserves'], ['足球', 'Football'],
];
const chineseMap = new Map(chineseAliases);
// Match longer labels first, in one pass: e.g. 中北美国联 must not first become
// 中北USA联, and 印度尼西亚 must not first become India尼西亚.
const chinesePattern = new RegExp(chineseAliases.map(([from]) => from)
  .sort((a, b) => b.length - a.length).join('|'), 'g');

export function providerEnglishName(value) {
  if (!value || typeof value !== 'object') return '';
  return firstFootballName(value.name_en, value.en_name, value.english_name,
    value.nameEn, value.englishName, value.en);
}

/** Prefer a nonempty provider English name; never let a blank field hide a fallback. */
export function firstFootballName(...values) {
  for (const value of values) {
    if (value && typeof value === 'object') {
      const name = firstFootballName(providerEnglishName(value), value.name);
      if (name) return name;
    } else if (typeof value === 'string' && value.trim()) {
      return value.trim();
    }
  }
  return '';
}

export function englishFootballName(value, kind = 'team') {
  const original = firstFootballName(value);
  if (!original) return '';
  let text = original.replace(chinesePattern, from => chineseMap.get(from));
  text = text.replace(/女(?=U\d|$)/g, ' Women ').replace(/\s+/g, ' ').trim();
  if (/^INTERF$/i.test(text)) return 'International Friendly';

  const latin = latinText(text);
  if (kind === 'league') return leagueAliases.get(key(latin)) ?? text;

  // Strip provider descriptors before resolving a country/club, including
  // already-transliterated names saved by earlier versions of the importer.
  const stripped = latin.replace(
    /^(?:(?:cau lac bo(?: bong da)?|clb|doi tuyen(?: quoc gia| qg)?|dtqg)\s+)+/i, '',
  ).replace(/\bNu\b/gi, 'Women').replace(/\s+/g, ' ').trim();
  if (!stripped) return text;
  const qualifiers = stripped.match(/\s+((?:(?:Women|U\d{1,2}|Reserves|II|B)\s*)+)$/i);
  const suffix = qualifiers?.[0] ?? '';
  const base = suffix ? stripped.slice(0, -suffix.length) : stripped;
  const alias = teamAliases.get(key(base));
  if (alias) return `${alias}${suffix}`.trim();

  // Keep ordinary Latin proper names (e.g. FC Köln) intact. Vietnamese proper
  // names without a known English alias use a readable Latin transliteration.
  const isVietnamese = /[ăâđêôơưĂÂĐÊÔƠƯ\u1ea0-\u1ef9]/u.test(text);
  const changedDescriptor = stripped !== latin;
  return (changedDescriptor || isVietnamese ? stripped : text)
    .replace(/([a-z])(?=U\d{1,2}\b)/g, '$1 ').trim();
}
