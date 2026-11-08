import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../network_endpoints.dart';
import '../services/function_gateway.dart';
import '../services/channel_playback_document.dart';
import '../widgets/channel_playback_frame.dart';

class ChannelPlaybackTestPage extends StatefulWidget {
  const ChannelPlaybackTestPage({super.key,required this.lineId,required this.channelId});
  final String lineId,channelId;
  @override
  State<ChannelPlaybackTestPage> createState()=>_ChannelPlaybackTestPageState();
}
class _ChannelPlaybackTestPageState extends State<ChannelPlaybackTestPage> {
  final nonce=List.generate(20,(_)=>Random.secure().nextInt(256)).join('-');
  late final Future<Map<String,dynamic>> preview=load();
  String? status;
  bool recorded=false;
  Future<Map<String,dynamic>> load()async{
    final raw=await FunctionGateway.invoke('stream-health',body:{'action':'preview','channel_line_id':widget.lineId});
    final result=Map<String,dynamic>.from(raw as Map);
    for(final base in publicApiBases()){
      try{
        final response=await http.get(Uri.parse('$base/channels/${widget.channelId}/streams')).timeout(const Duration(seconds:12));
        if(response.statusCode!=200)continue;
        final data=jsonDecode(response.body) as Map;
        for(final row in (data['streams'] as List? ?? const [])){
          if(row is Map&&row['id']==widget.lineId){result['line']=Map<String,dynamic>.from(row);return result;}
        }
      }catch(_){}
    }
    throw StateError('No configured playback route. Check this line’s DRM configuration and visibility.');
  }
  Future<void> onResult(Map<String,dynamic> data)async{
    if(recorded)return;recorded=true;
    try{
      final loaded=await preview;
      await FunctionGateway.invoke('stream-health',body:{'action':'record_playback','channel_line_id':widget.lineId,
        'version':loaded['version'],...data,'device':kIsWeb?'Admin Web':defaultTargetPlatform.name});
      if(mounted)setState(()=>status=data['status']=='verified'?'Decoded video verified on this device':data['status']=='unsupported'?'Unsupported on this device':'Video test failed on this device');
    }catch(_){if(mounted)setState(()=>status='The result could not be saved. Refresh and test again.');}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Test Video')),body:FutureBuilder<Map<String,dynamic>>(
    future:preview,builder:(context,snapshot){
      if(snapshot.hasError)return const Center(child:Padding(padding:EdgeInsets.all(20),child:Text('No configured playback route. Check DRM configuration and channel visibility.')));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      return Column(children:[if(status!=null)Padding(padding:const EdgeInsets.all(12),child:Text(status!)),
        Expanded(child:ChannelPlaybackFrame(html:channelPlaybackDocument(Map<String,dynamic>.from(snapshot.data!['line'] as Map),nonce),nonce:nonce,onResult:onResult))]);
    }));
}
