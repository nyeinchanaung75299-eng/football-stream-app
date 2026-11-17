// Fawa publishes its schedule clock as "(GMT+1)" on the source homepage.
// These labels lack a calendar date; never invent an ISO kickoff or match_time.
// Only convert when this explicit source-timezone marker is present.
export function fawaScheduleTimezoneConfirmed(html) {
  return /\bSchedule\s*\(\s*GMT\s*\+\s*1\s*\)/i.test(String(html));
}

export function fawaMyanmarTimeLabel(sourceLabel, timezoneConfirmed) {
  const text=String(sourceLabel??'').replace(/\s+/g,' ').trim();
  if(!text||!timezoneConfirmed)return text;
  const match=text.match(/^(.*?)(?:\s+)(\d{1,2}):(\d{2})\s*$/);
  if(!match)return text;
  const hour=Number(match[2]),minute=Number(match[3]);
  if(hour>23||minute>59)return text;
  // Fixed GMT+1 -> Myanmar UTC+6:30 is a 5h30m difference.
  const minutes=hour*60+minute+330;
  const localHour=Math.floor((minutes%1440)/60);
  const localMinute=minutes%60;
  const meridiem=localHour>=12?'PM':'AM';
  const shownHour=localHour%12||12;
  const hhmm=shownHour+':'+String(localMinute).padStart(2,'0')+' '+meridiem+' MMT';
  const nextDay=minutes>=1440?' (+1 day)':'';
  const league=match[1].trim();
  return (league?league+' • ':'')+hhmm+nextDay;
}
