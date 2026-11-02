import test from 'node:test';
import assert from 'node:assert/strict';
import {sourceMatchRows} from '../supabase/functions/_shared/source_match_rows.mjs';

const football = row => row.categoryId === 1;

test('Soco duplicate fixture merges rooms from normal and hot groups', () => {
  const input = {
    normal: [
      {scheduleId:'2026-11-02-a', categoryId:1,
       hostName:'Home',guestName:'Away',anchors:[
         {roomNum:'room1',nickName:'Host one'},
       ]},
      {scheduleId:'2026-11-02-b',categoryId:1,
       hostName:'Other',guestName:'Team',anchors:[]},
    ],
    hot: [
      {scheduleId:'2026-11-02-a',categoryId:1,
       hostName:'Home',guestName:'Away',anchors:[
         {roomNum:'room1',nickName:'Host one duplicated'},
         {roomNum:'room2',nickName:'Host two'},
       ]},
      {scheduleId:'2026-11-02-b',categoryId:1,
       hostName:'Other',guestName:'Team',anchorList:[
         {roomNum:'room3',nickName:'Host three'},
       ]},
    ],
  };
  const rows=sourceMatchRows(input,football);
  assert.equal(rows.length,2);
  const first=rows.find(m=>m.scheduleId==='2026-11-02-a');
  assert.equal(first.hot,true);
  assert.deepEqual(first.anchors.map(a=>a.roomNum),['room1','room2']);
  const second=rows.find(m=>m.scheduleId==='2026-11-02-b');
  assert.deepEqual(second.anchors.map(a=>a.roomNum),['room3']);
});

test('Soco preserves matchId-only fixtures rather than silently dropping them',()=>{
  const rows=sourceMatchRows({football:[
    {matchId:'soccer-1',categoryId:1,hostName:'ABC',guestName:'DEF',anchorList:[]},
    {gameId:'soccer-2',categoryId:1,hostName:'GHI',guestName:'JKL',anchors:[]},
    {matchId:'unrelated',categoryId:2,hostName:'Bad',guestName:'Other'},
  ]},football);
  assert.equal(rows.length,2);
  assert.deepEqual(rows.map(x=>x.matchId||x.gameId),['soccer-1','soccer-2']);
});

test('missing IDs are not guessed and duplicate non-football rows are excluded',()=>{
  const rows=sourceMatchRows({rows:[
    {categoryId:1,hostName:'No',guestName:'ID'},
    {scheduleId:'valid',categoryId:1,hostName:'Home',guestName:'Away'},
    {scheduleId:'other',categoryId:5,hostName:'Not',guestName:'Football'},
  ]},football);
  assert.equal(rows.length,1);
  assert.equal(rows[0].scheduleId,'valid');
});
