import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class ChannelPlaybackFrame extends StatefulWidget {
  const ChannelPlaybackFrame({super.key,required this.html,required this.nonce,required this.onResult});
  final String html,nonce;
  final ValueChanged<Map<String,dynamic>> onResult;
  @override
  State<ChannelPlaybackFrame> createState()=>_ChannelPlaybackFrameState();
}
class _ChannelPlaybackFrameState extends State<ChannelPlaybackFrame> {
  web.HTMLIFrameElement? frame;
  late final JSFunction listener;
  @override
  void initState(){super.initState();listener=((web.MessageEvent event){
    if(frame==null||event.source!=frame!.contentWindow)return;
    final data=event.data.dartify();
    if(data is Map){final row=Map<String,dynamic>.from(data);if(row['nonce']==widget.nonce)widget.onResult(row);}
  }).toJS;web.window.addEventListener('message',listener);}
  @override
  void dispose(){web.window.removeEventListener('message',listener);frame?.src='about:blank';super.dispose();}
  @override
  Widget build(BuildContext context)=>HtmlElementView.fromTagName(tagName:'iframe',onElementCreated:(element){
    frame=element as web.HTMLIFrameElement;
    // This is our generated document, never provider HTML. A real origin is
    // required for browser encrypted-media APIs used by configured ClearKey.
    frame!.setAttribute('sandbox','allow-scripts allow-same-origin');frame!.setAttribute('allow','autoplay; encrypted-media; fullscreen');
    frame!.style.width='100%';frame!.style.height='100%';frame!.style.border='0';frame!.srcdoc=widget.html.toJS;
  });
}
