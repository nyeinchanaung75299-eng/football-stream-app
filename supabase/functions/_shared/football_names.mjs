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

// Priority Chinese labels for the top five European leagues and 2026/27 UEFA
// league-phase clubs. Exact aliases only: no guessed club identities.
// Longest-label-first matching below prevents shorter names such as 巴黎 from
// taking precedence over 巴黎FC or 巴黎圣日耳曼.
export const priorityEuropeanAliases = [
  // Major competition label variants
  ["欧洲冠军联赛","UEFA Champions League"],
  ["欧洲冠军杯","UEFA Champions League"],
  ["欧冠联赛","UEFA Champions League"],
  ["欧冠资格赛","UEFA Champions League Qualifying"],
  ["欧洲冠军联赛资格赛","UEFA Champions League Qualifying"],
  ["欧洲足联欧洲联赛","UEFA Europa League"],
  ["欧罗巴联赛","UEFA Europa League"],
  ["欧洲联赛","UEFA Europa League"],
  ["欧联","UEFA Europa League"],
  ["欧联杯资格赛","UEFA Europa League Qualifying"],
  ["欧罗巴联赛资格赛","UEFA Europa League Qualifying"],
  ["英格兰足球超级联赛","English Premier League"],
  ["英格兰超级联赛","English Premier League"],
  ["英超联赛","English Premier League"],
  ["西班牙足球甲级联赛","Spanish La Liga"],
  ["西班牙甲级联赛","Spanish La Liga"],
  ["西甲联赛","Spanish La Liga"],
  ["德国足球甲级联赛","Bundesliga"],
  ["德国甲级联赛","Bundesliga"],
  ["德甲联赛","Bundesliga"],
  ["意大利足球甲级联赛","Italian Serie A"],
  ["意大利甲级联赛","Italian Serie A"],
  ["意甲联赛","Italian Serie A"],
  ["法国足球甲级联赛","French Ligue 1"],
  ["法国甲级联赛","French Ligue 1"],
  ["法甲联赛","French Ligue 1"],
  // Premier League additional names and regional variants
  ["曼彻斯特联队","Manchester United"],
  ["曼徹斯特聯","Manchester United"],
  ["曼彻斯特城足球俱乐部","Manchester City"],
  ["曼徹斯特城","Manchester City"],
  ["阿仙奴","Arsenal"],
  ["車路士","Chelsea"],
  ["纽卡斯尔","Newcastle United"],
  ["紐卡素","Newcastle United"],
  ["纽卡素","Newcastle United"],
  ["西汉姆联队","West Ham United"],
  ["西汉姆","West Ham United"],
  ["布莱顿霍夫","Brighton & Hove Albion"],
  ["阿士东维拉","Aston Villa"],
  ["富咸","Fulham"],
  ["诺丁汉","Nottingham Forest"],
  ["利兹联队","Leeds United"],
  ["伊普斯维奇城","Ipswich Town"],
  ["热刺队","Tottenham Hotspur"],
  // La Liga additional names and regional variants
  ["皇家馬德里","Real Madrid"],
  ["皇马","Real Madrid"],
  ["马德里体育会","Atletico Madrid"],
  ["马竞","Atletico Madrid"],
  ["馬德里競技","Atletico Madrid"],
  ["巴塞隆纳","Barcelona"],
  ["巴塞隆納","Barcelona"],
  ["巴萨","Barcelona"],
  ["FC巴塞罗那","Barcelona"],
  ["毕尔巴鄂","Athletic Bilbao"],
  ["巴列卡诺闪电","Rayo Vallecano"],
  ["赫塔费","Getafe"],
  ["加的斯","Cadiz"],
  ["莱加内斯","Leganes"],
  ["巴拉多利德","Real Valladolid"],
  ["皇家奥维耶多","Real Oviedo"],
  ["奥维耶多","Real Oviedo"],
  ["格拉纳达","Granada"],
  ["埃瓦尔","Eibar"],
  ["拉科鲁尼亚","Deportivo La Coruna"],
  // Bundesliga additional names and regional variants
  ["拜仁","Bayern Munich"],
  ["多特","Borussia Dortmund"],
  ["多蒙特","Borussia Dortmund"],
  ["莱比锡红牛","RB Leipzig"],
  ["VfB斯图加特","VfB Stuttgart"],
  ["门兴","Borussia Monchengladbach"],
  ["波鸿","VfL Bochum"],
  ["荷尔斯泰因基尔","Holstein Kiel"],
  ["基尔荷尔斯泰因","Holstein Kiel"],
  ["菲尔特","Greuther Furth"],
  ["雷根斯堡","Jahn Regensburg"],
  ["帕德伯恩","SC Paderborn 07"],
  // Serie A additional names and regional variants
  ["國際米蘭","Inter Milan"],
  ["国际米蘭","Inter Milan"],
  ["AC米蘭","AC Milan"],
  ["米兰AC","AC Milan"],
  ["尤文","Juventus"],
  ["祖雲達斯","Juventus"],
  ["拿玻里","Napoli"],
  ["卡利亚里","Cagliari"],
  ["克雷莫内塞","Cremonese"],
  ["克雷莫纳","Cremonese"],
  ["比萨","Pisa"],
  ["恩波利","Empoli"],
  ["蒙扎","Monza"],
  ["弗罗西诺内","Frosinone"],
  ["威尼斯","Venezia"],
  ["斯佩齐亚","Spezia"],
  ["巴勒莫","Palermo"],
  // Ligue 1 additional names and regional variants
  ["巴黎FC","Paris FC"],
  ["巴黎足球俱乐部","Paris FC"],
  ["巴黎圣日尔曼","Paris Saint-Germain"],
  ["巴黎聖日耳門","Paris Saint-Germain"],
  ["巴黎","Paris Saint-Germain"],
  ["昂热","Angers"],
  ["欧塞尔","Auxerre"],
  ["圣埃蒂安","Saint-Etienne"],
  ["圣艾蒂安","Saint-Etienne"],
  ["兰斯","Reims"],
  ["蒙彼利埃","Montpellier"],
  ["克莱蒙","Clermont Foot"],
  ["阿雅克肖","Ajaccio"],
  ["特鲁瓦","Troyes"],
  ["格勒诺布尔","Grenoble"],
  // 2026/27 Champions League participants beyond the five leagues
  ["拉斯克","LASK"],
  ["萨巴赫","Sabah FK"],
  ["布鲁日","Club Brugge"],
  ["布拉格斯拉维亚","Slavia Prague"],
  ["布拉格斯拉維亞","Slavia Prague"],
  ["雅典AEK","AEK Athens"],
  ["AEK雅典","AEK Athens"],
  ["博德闪耀","Bodø/Glimt"],
  ["博德格林特","Bodø/Glimt"],
  ["维京足球俱乐部","Viking FK"],
  ["布拉迪斯拉发斯洛万","Slovan Bratislava"],
  ["斯洛万布拉迪斯拉发","Slovan Bratislava"],
  ["布拉迪斯拉发","Slovan Bratislava"],
  ["顿涅茨克矿工","Shakhtar Donetsk"],
  ["顿涅茨克矿工队","Shakhtar Donetsk"],
  ["费内巴赫","Fenerbahce"],
  // 2026/27 Europa League participants beyond the five leagues
  ["安德莱赫特","Anderlecht"],
  ["安德列赫特","Anderlecht"],
  ["阿拉拉特亚美尼亚","Ararat-Armenia"],
  ["阿尔克马尔","AZ Alkmaar"],
  ["贝斯克塔斯","Besiktas"],
  ["采列","NK Celje"],
  ["费伦茨瓦罗斯","Ferencvaros"],
  ["萨格勒布迪纳摩","Dinamo Zagreb"],
  ["贝尔谢巴夏普尔","Hapoel Be'er Sheva"],
  ["贝尔谢巴工人","Hapoel Be'er Sheva"],
  ["雅盖隆尼亚","Jagiellonia Bialystok"],
  ["比亚韦斯托克雅盖隆","Jagiellonia Bialystok"],
  ["波兹南莱赫","Lech Poznan"],
  ["莱赫波兹南","Lech Poznan"],
  ["索菲亚列夫斯基","Levski Sofia"],
  ["利勒斯特罗姆","Lillestrom"],
  ["利勒斯特伦","Lillestrom"],
  ["奈梅亨","NEC Nijmegen"],
  ["尼美根","NEC Nijmegen"],
  ["OFI克里特","OFI Crete"],
  ["克里特OFI","OFI Crete"],
  ["奥林匹亚科斯","Olympiacos"],
  ["奥林匹亚克斯","Olympiacos"],
  ["奥莫尼亚","Omonia Nicosia"],
  ["尼科西亚奥莫尼亚","Omonia Nicosia"],
  ["萨尔茨堡红牛","Red Bull Salzburg"],
  ["萨尔茨堡","Red Bull Salzburg"],
  ["布拉格斯巴达","Sparta Prague"],
  ["格拉茨风暴","Sturm Graz"],
  ["圣吉罗斯联合","Union Saint-Gilloise"],
  ["圣吉罗斯","Union Saint-Gilloise"],
  ["比尔森胜利","Viktoria Plzen"],
  ["比尔森","Viktoria Plzen"],
  ["托雷恩斯","Torreense"],
  ["托伦斯","Torreense"],
];

const chineseAliases = [
  ...priorityEuropeanAliases,
  // Common clubs and competition labels verified against their established
  // English names. These are aliases, not inferred fixture/team identities.
  ['欧冠杯', 'UEFA Champions League'], ['欧冠', 'UEFA Champions League'],
  ['欧罗巴杯', 'UEFA Europa League'], ['欧联杯', 'UEFA Europa League'],
  ['欧协联', 'UEFA Conference League'], ['世俱杯', 'FIFA Club World Cup'],
  ['英联杯', 'EFL Cup'], ['英甲', 'English League One'], ['英乙', 'English League Two'],
  ['英议联', 'English National League'], ['德丙', '3. Liga'],
  ['德地区', 'German Regionalliga'], ['德青联', 'German Youth League'],
  ['西乙', 'Spanish Segunda Division'], ['西杯', 'Copa del Rey'],
  ['意乙', 'Italian Serie B'], ['意杯', 'Coppa Italia'],
  ['法乙', 'French Ligue 2'], ['法丙', 'French National'],
  ['葡超', 'Portuguese Primeira Liga'], ['葡甲', 'Portuguese Liga Portugal 2'],
  ['荷甲', 'Netherlands Eredivisie'], ['荷乙', 'Netherlands Eerste Divisie'],
  ['荷丙', 'Netherlands Tweede Divisie'], ['比甲', 'Belgian Pro League'],
  ['苏超', 'Scottish Premiership'], ['苏冠', 'Scottish Championship'],
  ['瑞士超', 'Swiss Super League'], ['瑞典超', 'Swedish Allsvenskan'],
  ['挪超', 'Norwegian Eliteserien'], ['丹麦超', 'Danish Superliga'],
  ['丹麦甲', 'Danish 1st Division'], ['奥甲', 'Austrian Bundesliga'],
  ['土超', 'Turkish Super Lig'], ['土甲', 'Turkish 1. Lig'],
  ['俄超', 'Russian Premier League'], ['乌克超', 'Ukrainian Premier League'],
  ['波兰甲', 'Polish Ekstraklasa'], ['捷甲', 'Czech First League'],
  ['希腊超', 'Greek Super League'], ['塞尔超', 'Serbian SuperLiga'],
  ['克亚甲', 'Croatian First Football League'], ['罗甲', 'Romanian Liga I'],
  ['保甲', 'Bulgarian First League'], ['匈甲', 'Hungarian NB I'],
  ['立陶甲', 'Lithuanian A Lyga'], ['格鲁甲', 'Georgian Erovnuli Liga'],
  ['爱沙甲', 'Estonian Meistriliiga'], ['斯伐超', 'Slovak First League'],
  ['冰岛超', 'Icelandic Besta deild'], ['以超', 'Israeli Premier League'],
  ['沙特联', 'Saudi Pro League'], ['卡塔尔联', 'Qatar Stars League'],
  ['阿联酋超', 'UAE Pro League'], ['伊朗超', 'Iranian Persian Gulf Pro League'],
  ['澳超', 'Australian A-League'], ['印尼甲', 'Indonesia Liga 1'],
  ['泰超', 'Thai League 1'], ['泰甲', 'Thai League 2'],
  ['新加坡联', 'Singapore Premier League'], ['印度超', 'Indian Super League'],
  ['巴西甲', 'Brazil Serie A'], ['阿甲', 'Argentina Primera Division'],
  ['墨西超', 'Mexico Liga MX'], ['美乙', 'USL Championship'],
  ['中乙', 'China League Two'], ['中女超', "Chinese Women's Super League"],
  ['中U21', 'Chinese U21 League'], ['日职丙', 'Japanese J3 League'],
  ['韩K2联', 'Korean K League 2'], ['韩K3联', 'Korean K3 League'],
  ['帕德博恩', 'SC Paderborn 07'], ['斯图加特', 'VfB Stuttgart'],
  ['柏林联合', '1. FC Union Berlin'], ['埃弗斯堡', 'SV 07 Elversberg'],
  ['奥格斯堡', 'FC Augsburg'], ['霍芬海姆', 'TSG Hoffenheim'],
  ['汉堡', 'Hamburger SV'], ['美因茨', 'Mainz 05'],
  ['勒沃库森', 'Bayer Leverkusen'], ['多特蒙德', 'Borussia Dortmund'],
  ['法兰克福', 'Eintracht Frankfurt'], ['门兴格拉德巴赫', 'Borussia Monchengladbach'],
  ['弗赖堡', 'SC Freiburg'], ['沃尔夫斯堡', 'VfL Wolfsburg'],
  ['云达不莱梅', 'Werder Bremen'], ['海登海姆', '1. FC Heidenheim'],
  ['圣保利', 'FC St. Pauli'], ['科隆', 'FC Cologne'],
  ['RB莱比锡', 'RB Leipzig'], ['莱比锡', 'RB Leipzig'],
  ['沙尔克04', 'Schalke 04'], ['汉诺威96', 'Hannover 96'],
  ['杜塞尔多夫', 'Fortuna Dusseldorf'], ['卡尔斯鲁厄', 'Karlsruher SC'],
  ['纽伦堡', '1. FC Nuremberg'], ['凯泽斯劳滕', '1. FC Kaiserslautern'],
  ['达姆施塔特', 'SV Darmstadt 98'], ['柏林赫塔', 'Hertha BSC'],
  ['巴列卡诺', 'Rayo Vallecano'], ['毕尔巴鄂竞技', 'Athletic Bilbao'],
  ['阿拉维斯', 'Deportivo Alaves'], ['里尔', 'Lille'],
  ['勒阿弗尔', 'Le Havre'], ['国际米兰', 'Inter Milan'], ['帕尔马', 'Parma'],
  ['塞维利亚', 'Sevilla'], ['皇家贝蒂斯', 'Real Betis'],
  ['皇家社会', 'Real Sociedad'], ['塞尔塔', 'Celta Vigo'],
  ['奥萨苏纳', 'Osasuna'], ['赫塔菲', 'Getafe'], ['赫罗纳', 'Girona'],
  ['西班牙人', 'Espanyol'], ['瓦伦西亚', 'Valencia'],
  ['马洛卡', 'Mallorca'], ['莱万特', 'Levante'], ['埃尔切', 'Elche'],
  ['尤文图斯', 'Juventus'], ['AC米兰', 'AC Milan'], ['那不勒斯', 'Napoli'],
  ['罗马', 'AS Roma'], ['拉齐奥', 'Lazio'], ['亚特兰大', 'Atalanta'],
  ['佛罗伦萨', 'Fiorentina'], ['博洛尼亚', 'Bologna'], ['都灵', 'Torino'],
  ['热那亚', 'Genoa'], ['乌迪内斯', 'Udinese'], ['萨索洛', 'Sassuolo'],
  ['莱切', 'Lecce'], ['科莫', 'Como'], ['维罗纳', 'Hellas Verona'],
  ['马赛', 'Marseille'], ['里昂', 'Lyon'], ['摩纳哥', 'Monaco'],
  ['尼斯', 'Nice'], ['雷恩', 'Rennes'], ['斯特拉斯堡', 'Strasbourg'],
  ['南特', 'Nantes'], ['朗斯', 'Lens'], ['布雷斯特', 'Brest'],
  ['图卢兹', 'Toulouse'], ['梅斯', 'Metz'], ['洛里昂', 'Lorient'],
  ['埃弗顿', 'Everton'], ['西汉姆联', 'West Ham United'],
  ['纽卡斯尔联', 'Newcastle United'], ['水晶宫', 'Crystal Palace'],
  ['狼队', 'Wolverhampton Wanderers'], ['南安普顿', 'Southampton'],
  ['莱斯特城', 'Leicester City'], ['伯恩利', 'Burnley'],
  ['谢菲尔德联', 'Sheffield United'], ['考文垂', 'Coventry City'],
  ['西布罗姆维奇', 'West Bromwich Albion'], ['伯明翰', 'Birmingham City'],
  ['诺维奇', 'Norwich City'], ['斯旺西', 'Swansea City'],
  ['查尔顿', 'Charlton Athletic'], ['布里斯托城', 'Bristol City'],
  ['牛津联队', 'Oxford United'], ['普利茅斯', 'Plymouth Argyle'],
  ['诺茨郡', 'Notts County'], ['AFC温布尔登', 'AFC Wimbledon'],
  ['阿贾克斯', 'Ajax'], ['埃因霍温', 'PSV Eindhoven'],
  ['费耶诺德', 'Feyenoord'], ['特温特', 'FC Twente'],
  ['本菲卡', 'Benfica'], ['波尔图', 'FC Porto'], ['葡萄牙体育', 'Sporting CP'],
  ['加拉塔萨雷', 'Galatasaray'], ['费内巴切', 'Fenerbahce'],
  ['贝西克塔斯', 'Besiktas'], ['凯尔特人', 'Celtic'], ['格拉斯哥流浪者', 'Rangers'],
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
    .replace(/([a-z0-9])(?=U\d{1,2}\b)/gi, '$1 ').trim();
}

const nonLatinDisplay = /[^\p{Script=Latin}\p{N}\p{P}\p{Z}\p{S}\p{M}]/u;

function displayIdentity(value) {
  const original = String(value ?? '').trim();
  if (/^[A-Za-z0-9_-]{1,64}$/.test(original)) return original;
  let hash = 2166136261;
  for (let index = 0; index < original.length; index++) hash = Math.imul(hash ^ original.charCodeAt(index), 16777619);
  return (hash >>> 0).toString(16);
}

/** Strict display only. Unknown proper names remain in original_* metadata. */
export function englishSourceDisplayName(value, kind, fallback) {
  const normalized = englishFootballName(value, kind);
  return normalized && !nonLatinDisplay.test(normalized) ? normalized : fallback;
}

export function sourceFootballNames(row, strictEnglish = false) {
  const leagueId = displayIdentity(row?.subCateId ?? row?.leagueId ?? row?.competitionId ?? row?.subCateName ?? '');
  const originalHome = firstFootballName(row?.hostName, row?.homeName, row?.home_team,
    row?.homeTeamName, row?.hostTeamName, row?.team1Name,
    row?.hostTeam, row?.homeTeam, row?.host, row?.home, row?.teams?.home, row?.team1);
  const originalAway = firstFootballName(row?.guestName, row?.awayName, row?.away_team,
    row?.awayTeamName, row?.guestTeamName, row?.team2Name,
    row?.guestTeam, row?.awayTeam, row?.guest, row?.away, row?.teams?.away, row?.team2);
  const originalLeague = firstFootballName(row?.subCateName, row?.leagueName,
    row?.competitionName, row?.categoryName, row?.competition, row?.league);
  const sourceId = displayIdentity(row?.scheduleId ?? row?.schedule_id ?? row?.fixtureId ?? row?.id ??
    [originalHome, originalAway, originalLeague].join('|'));
  const home = [row?.hostNameEn, row?.hostNameEN, row?.hostName_en,
    row?.homeNameEn, row?.homeTeamNameEn, row?.hostTeamNameEn,
    row?.home_name_en, row?.team1NameEn,
    providerEnglishName(row?.hostTeam), providerEnglishName(row?.homeTeam),
    providerEnglishName(row?.host), providerEnglishName(row?.home),
    providerEnglishName(row?.teams?.home), providerEnglishName(row?.team1),
    originalHome];
  const away = [row?.guestNameEn, row?.guestNameEN, row?.guestName_en,
    row?.awayNameEn, row?.awayTeamNameEn, row?.guestTeamNameEn,
    row?.away_name_en, row?.team2NameEn,
    providerEnglishName(row?.guestTeam), providerEnglishName(row?.awayTeam),
    providerEnglishName(row?.guest), providerEnglishName(row?.away),
    providerEnglishName(row?.teams?.away), providerEnglishName(row?.team2),
    originalAway];
  const league = [row?.subCateNameEn, row?.subCateNameEN, row?.leagueNameEn, row?.leagueNameEN,
    row?.competitionNameEn, providerEnglishName(row?.competition), providerEnglishName(row?.league), originalLeague];
  const format = (values, kind, fallback) => {
    if (!strictEnglish) return englishFootballName(firstFootballName(...values), kind) || fallback;
    for (const value of values) {
      const display = englishSourceDisplayName(value, kind, '');
      if (display) return display;
    }
    return fallback;
  };
  const result = {
    home_team: format(home, 'team', 'Home team (' + sourceId + ')'),
    away_team: format(away, 'team', 'Away team (' + sourceId + ')'),
    league: format(league, 'league', 'Football league (' + leagueId + ')'),
  };
  if (!strictEnglish) return result;
  // Canonical fields already contain the display names. Do not duplicate them
  // into *_en or duplicate unchanged originals: 4,000-row catalogs have a 2MiB
  // relay body limit. Raw teams are retained only when needed for identity.
  if (originalHome && originalHome !== result.home_team) result.original_home_team = originalHome;
  if (originalAway && originalAway !== result.away_team) result.original_away_team = originalAway;
  return result;
}

/** Streamer proper nicknames are identities, not team-name translations. */
export function englishStreamerName(anchor, index, prefix = 'Streamer') {
  const original = firstFootballName(anchor?.nickName, anchor?.nick_name, anchor?.name);
  const provided = firstFootballName(anchor?.nickNameEn, anchor?.nick_name_en, anchor?.nameEn, providerEnglishName(anchor));
  const label = provided && !nonLatinDisplay.test(provided)
    ? provided : original && !nonLatinDisplay.test(original) ? latinText(original) : prefix + ' ' + (index + 1);
  const language = /[粤粵][语語]|cantonese/i.test(original) ? 'Cantonese'
    : /[国國][语語]|普通[话話]|mandarin/i.test(original) ? 'Mandarin' : null;
  return {
    nick_name: language && !new RegExp(language, 'i').test(label) ? label + ' (' + language + ')' : label,
    original_nick_name: original || null, import_name: original || prefix + ' ' + (index + 1),
    commentary_language: language,
  };
}
