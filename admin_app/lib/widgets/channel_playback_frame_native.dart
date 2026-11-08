import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ChannelPlaybackFrame extends StatelessWidget {
  const ChannelPlaybackFrame({super.key,required this.html,required this.nonce,required this.onResult});
  final String html,nonce;
  final ValueChanged<Map<String,dynamic>> onResult;
  @override
  Widget build(BuildContext context)=>InAppWebView(
    initialData:InAppWebViewInitialData(data:html,baseUrl:WebUri('https://nyeinchanaung75299-eng.github.io/football-stream-app/admin/')),
    initialSettings:InAppWebViewSettings(javaScriptEnabled:true,mediaPlaybackRequiresUserGesture:true,allowsInlineMediaPlayback:true),
    onWebViewCreated:(controller)=>controller.addJavaScriptHandler(handlerName:'ncaProbe',callback:(args){
      if(args.isNotEmpty&&args.first is Map){final row=Map<String,dynamic>.from(args.first as Map);if(row['nonce']==nonce)onResult(row);}
    }),
  );
}
