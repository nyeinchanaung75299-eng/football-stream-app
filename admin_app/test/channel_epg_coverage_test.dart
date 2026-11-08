import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/tv_schedule_service.dart';
import 'package:football_admin/services/channel_playback_document.dart';
void main(){
  test('EPG binding, current programmes and missing guide stay separate',(){
    final now=DateTime.utc(2026,11,8,12);
    final base={'id':'test','name':'Sports','category':'Sports','epg_id':'station','epg_source':'US2'};
    expect(TvScheduleChannel.fromJson({...base,'matchedEPG':false}).coverageAt(now),'awaiting_guide');
    expect(TvScheduleChannel.fromJson({'id':'test','name':'Sports'}).coverageAt(now),'not_linked');
    expect(TvScheduleChannel.fromJson({...base,'matchedEPG':true,'programmes':[{
      'title':'Napoli vs Inter','start':now.millisecondsSinceEpoch,'end':now.add(const Duration(hours:2)).millisecondsSinceEpoch,
    }]}).coverageAt(now),'ready');
  });
  test('playback document escapes configuration and verifies frames rather than HTTP status',(){
    final html=channelPlaybackDocument({'stream_url':'https://example.org/</script><script>injected()'},'nonce');
    expect(html.contains('</script><script>injected()'),isFalse);
    expect(html.contains('getVideoPlaybackQuality'),isTrue);
    expect(html.contains('v.videoWidth>0'),isTrue);
  });
}
