# V6.1 Adaptive Quality Clarification

This corrects the meaning of "resolution".

## One URL, many qualities
For an adaptive HLS master playlist (.m3u8) or DASH manifest (.mpd), Admin uploads ONE URL.

Example:
- Server name: Main
- Stream type: HLS
- URL: one master .m3u8

If that manifest advertises 360p, 480p, 720p and 1080p, the native player detects those tracks automatically.

The top-right player menu becomes:
- Auto
- 1080p
- 720p
- 480p
- 360p

No separate URL is required for each resolution.

## Multiple links mean servers, not qualities
If Admin adds more than one link to the same match, those are treated as:
- Server 1
- Server 2
- Backup
etc.

Each HLS/DASH server can independently expose its own adaptive qualities.

## Direct FLV / MP4
A normal progressive FLV or MP4 URL usually contains one video quality. If the media itself does not expose multiple video tracks, there is nothing for the quality picker to switch between.
