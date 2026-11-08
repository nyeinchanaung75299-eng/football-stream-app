import 'dart:convert';

String channelPlaybackDocument(Map<String,dynamic> line, String nonce) {
  final config=jsonEncode({'url':line['stream_url'],'type':line['stream_type'],'keyId':line['key_id'],'keyData':line['key_data'],'nonce':nonce})
      .replaceAll('<',r'\u003c').replaceAll('>',r'\u003e');
  return '''<!doctype html><html><meta name="viewport" content="width=device-width,initial-scale=1"><style>
  body{margin:0;background:#07100c;color:#e2f6e8;font:15px system-ui}video{width:100%;max-height:70vh;background:#000}button{padding:14px;margin:12px;border:0;border-radius:12px;background:#a5d7a7;font-size:16px}p{padding:0 12px}</style>
  <video id="v" playsinline muted controls></video><button id="start">Start video test</button><p id="state">This test verifies decoded video frames on this device.</p>
  <script src="https://ajax.googleapis.com/ajax/libs/shaka-player/5.2.12/shaka-player.compiled.js"></script>
  <script>
  const c=$config,v=document.getElementById('v'),s=document.getElementById('state');let done=false,frames=0,startTime=0,player,timer;
  function finish(status){if(done)return;done=true;clearTimeout(timer);v.pause();const q=v.getVideoPlaybackQuality?.();
   const r={nonce:c.nonce,status,frames:Math.max(frames,q?.totalVideoFrames||0),width:v.videoWidth,height:v.videoHeight,advanced:v.currentTime-startTime};
   s.textContent=status==='verified'?'Video frames decoded successfully.':status==='unsupported'?'This device does not support this playback configuration.':'Video did not start on this device.';
   if(window.flutter_inappwebview)window.flutter_inappwebview.callHandler('ncaProbe',r);else parent.postMessage(r,'*');player?.destroy();}
  function frame(){frames++;if(!done)v.requestVideoFrameCallback?.(frame);}
  document.getElementById('start').onclick=async()=>{document.getElementById('start').disabled=true;s.textContent='Checking video…';
   timer=setTimeout(()=>finish('failed'),25000);v.muted=true;v.requestVideoFrameCallback?.(frame);startTime=v.currentTime;
   try{
    if(c.type==='flv'){finish('unsupported');return;}
    if(c.type==='dash'||c.keyId||!v.canPlayType('application/vnd.apple.mpegurl')){
     if(!window.shaka){finish('unsupported');return;}shaka.polyfill.installAll();
     if(!shaka.Player.isBrowserSupported()){finish('unsupported');return;}
     player=new shaka.Player();await player.attach(v);
     if(c.keyId&&c.keyData){const keys={};keys[c.keyId]=c.keyData;player.configure({drm:{clearKeys:keys}});}
     player.addEventListener('error',e=>finish([6001,6002].includes(e.detail?.code)?'unsupported':'failed'));
     await player.load(c.url,null,c.type==='dash'?'application/dash+xml':c.type==='hls'?'application/x-mpegurl':c.type==='mp4'?'video/mp4':undefined);
    }else v.src=c.url;
    await v.play();
    const interval=setInterval(()=>{if(done){clearInterval(interval);return;}const q=v.getVideoPlaybackQuality?.();
     if(Math.max(frames,q?.totalVideoFrames||0)>0&&v.videoWidth>0&&v.videoHeight>0&&v.currentTime-startTime>0.2)finish('verified');},200);
   }catch(e){finish([6001,6002].includes(e.code)?'unsupported':'failed');}
  };
  </script></html>''';
}
