import test from 'node:test';
import assert from 'node:assert/strict';
import {fawaScheduleTimezoneConfirmed,fawaMyanmarTimeLabel} from '../supabase/functions/_shared/fawa_schedule_time.mjs';

test('Fawa timezone is accepted only from its explicitly labeled schedule',()=>{
  assert.equal(fawaScheduleTimezoneConfirmed('<h1>Press to Refresh The Schedule (GMT+1)</h1>'),true);
  assert.equal(fawaScheduleTimezoneConfirmed('Schedule GMT+1'),false);
  assert.equal(fawaScheduleTimezoneConfirmed('<p>Schedule (GMT+2)</p>'),false);
});

test('Fawa 17:00 GMT+1 becomes 10:30 PM Myanmar, same day',()=>{
  assert.equal(fawaMyanmarTimeLabel('Africa Cup of Nations 17:00',true),
    'Africa Cup of Nations • 10:30 PM MMT');
});

test('Fawa 19:00 GMT+1 becomes 12:30 AM Myanmar, next day',()=>{
  assert.equal(fawaMyanmarTimeLabel('Hockey Champions League 19:00',true),
    'Hockey Champions League • 12:30 AM MMT (+1 day)');
});

test('Unknown timezone, invalid clock and missing kickoff remain unchanged',()=>{
  for(const source of ['Africa Cup of Nations 17:00','Football 24:01','Football 18:99','Football']){
    assert.equal(fawaMyanmarTimeLabel(source,false),source);
  }
  assert.equal(fawaMyanmarTimeLabel('Football 24:01',true),'Football 24:01');
  assert.equal(fawaMyanmarTimeLabel('Football',true),'Football');
});

test('Source GMT+1 clock remains label-only, never invent a match date',()=>{
  assert.equal(fawaMyanmarTimeLabel('Football 23:50',true),'Football • 5:20 AM MMT (+1 day)');
});
