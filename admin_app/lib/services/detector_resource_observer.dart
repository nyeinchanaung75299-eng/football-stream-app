import 'stream_detector_service.dart';

/// All frames observe their own loaded media. Only the CURRENT top document
/// forwards events to Dart; detached frames cannot contribute to a new page.
/// This is passive: no fetch overrides, cookies, keys, or media downloads.
const detectorResourceObserver = r'''
(() => {
  if (window.__ncaDetectorScan) return;
  const tag = 'nca-detector-resources-v1';
  const isTop = window === window.top;
  const id = Date.now().toString(36) + Math.random().toString(36).slice(2);
  const seen = new Set();
  const mediaPattern = /\.(m3u8|mpd|mp4|flv)$/i;
  const valid = raw => {
    try {
      const u = new URL(raw, document.baseURI);
      if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) return null;
      const format = ['format','type','extension'].map(k=>u.searchParams.get(k)||'').join(' ');
      return mediaPattern.test(u.pathname) || /\b(m3u8|hls|mpd|dash|mp4|flv)\b/i.test(format) ? u.href : null;
    } catch (_) { return null; }
  };
  const descendant = source => {
    let remaining = 64;
    const visit = (parent, depth) => {
      if (parent === source) return true;
      if (depth > 6 || --remaining < 0) return false;
      try { for (let i=0;i<parent.frames.length;i++) if (visit(parent.frames[i],depth+1)) return true; } catch (_) {}
      return false;
    };
    return visit(window,0);
  };
  const forward = event => {
    const bridge = window.flutter_inappwebview;
    if (!bridge || !bridge.callHandler) return;
    // srcdoc/about:blank/blob player documents have no public Referer URL.
    // Keep their observed media and use the current public parent as a guess;
    // real native request headers, when present, still take precedence.
    let frameUrl = event.frameUrl;
    try {
      const frame = new URL(frameUrl);
      if (!['http:', 'https:'].includes(frame.protocol) || frame.username || frame.password) frameUrl = location.href;
    } catch (_) { frameUrl = location.href; }
    bridge.callHandler('NcaMediaResources', {
      documentId: id, pageUrl: location.href,
      frameUrl, urls: event.urls, mediaUrls: event.mediaUrls
    }).catch(()=>{});
  };
  if (isTop) {
    window.__ncaDetectorDocumentId = id;
    window.addEventListener('message', event => {
      const data = event.data;
      if (data && data.tag === tag && descendant(event.source)) forward(data);
    });
  }
  const report = (rawUrls, rawMedia=[]) => {
    const urls = [...new Set(rawUrls.map(valid).filter(Boolean))].slice(0,100);
    const mediaUrls = [...new Set(rawMedia.map(valid).filter(Boolean))].slice(0,100);
    if (!urls.length && !mediaUrls.length) return;
    const event = {tag,frameUrl:location.href,urls,mediaUrls};
    if (isTop) forward(event); else window.top.postMessage(event,'*');
  };
  const scan = () => {
    const media=[];
    document.querySelectorAll('video, video source, audio, audio source').forEach(el=>{
      if(el.currentSrc)media.push(el.currentSrc); if(el.src)media.push(el.src);
    });
    const resources = performance.getEntriesByType('resource').map(e=>e.name);
    report([...resources,...media],media);
  };
  window.__ncaDetectorScan = scan;
  try {
    new PerformanceObserver(list=>{
      const urls=list.getEntries().map(e=>e.name).filter(name=>{
        const value=valid(name); if(!value||seen.has(value))return false;
        seen.add(value); if(seen.size>500)seen.clear(); return true;
      });
      if(urls.length) { report(urls); scan(); }
    }).observe({entryTypes:['resource']});
  } catch (_) {}
  window.addEventListener('flutterInAppWebViewPlatformReady',scan);
  window.addEventListener('load',scan);
  document.addEventListener('play',scan,true);
  document.addEventListener('loadedmetadata',scan,true);
  // A child can load a player after the main page's load event. Each frame's
  // local scan retains that route, including cross-origin frames and MSE.
  const timer=setInterval(scan,1500);
  window.addEventListener('pagehide',()=>clearInterval(timer),{once:true});
  scan();
})();
''';

class DetectorResourceEvent {
  DetectorResourceEvent(this.documentId, this.pageUrl, this.frameUrl,
      this.streams, this.mediaUrls);
  final String documentId, pageUrl, frameUrl;
  final List<DetectedStream> streams;
  final List<String> mediaUrls;

  static DetectorResourceEvent? parse(dynamic value) {
    if (value is! Map) return null;
    final id = value['documentId'];
    final page = _page(value['pageUrl']);
    final frame = _page(value['frameUrl']);
    if (id is! String ||
        id.isEmpty ||
        id.length > 100 ||
        page == null ||
        frame == null) return null;
    final urls = value['urls'];
    final media = value['mediaUrls'];
    if (urls is! List || media is! List) return null;
    final streams = <String, DetectedStream>{};
    for (final raw in [...urls.take(100), ...media.take(100)]) {
      if (raw is! String || raw.length > 16384) continue;
      final stream = DetectedStream.fromRequest(raw, pageUrl: frame);
      if (stream != null) streams[stream.url] = stream;
    }
    return DetectorResourceEvent(
        id,
        page,
        frame,
        streams.values.toList(),
        media
            .whereType<String>()
            .where(streams.containsKey)
            .take(100)
            .toList());
  }

  static String? _page(dynamic value) {
    if (value is! String || value.length > 16384) return null;
    final uri = Uri.tryParse(value);
    return uri != null &&
            const {'https', 'http'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri.toString()
        : null;
  }
}
