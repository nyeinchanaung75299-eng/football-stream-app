# V7.9 Fixed-size full-screen player

Default player sizing is now FILL on Android and Web.

FILL:
- exact full-screen player bounds on different phone aspect ratios
- no black letterbox bars
- no zoom/crop
- may stretch the image slightly when stream and phone aspect ratios differ

FIT:
- available from the tap controls
- preserves the source aspect ratio exactly
- can show black bars

Zoom/crop is not used as the default mode.
Android 11+ immersive behavior remains supported.
