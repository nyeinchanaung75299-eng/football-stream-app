# Xoilac / Camel1 support (2026-10-28)

- Xoilac public football fixtures are parsed from the supplied site's HTML.
  Stream lookup reads only its published literal list_stream and urlStream
  values, with fixed provider/player/media host validation and bounded reads.
  No JS evaluation, login bypass, credential capture or host substitution.
- The inspected backend lookup currently receives HTTP403 from Xoilac's player
  host. The app reports unavailability and offers the original Xoilac page;
  it does not claim that extraction or proxy playback works during that denial.
  A successful public lookup can use the existing protected playback pipeline.
- Camel1 public fixture metadata is available. Its player explicitly asks users
  to log in. Both picker and Viewer offer Open Camel1 on the original site,
  clearly labelled as requiring sign-in. No app credentials are transferred.
- A bounded, validated same-origin canonical redirect is supported; other
  redirect destinations are rejected. Metadata failures are not empty success.
- Existing four channels each have one line. Editor hides server labels/add-line
  controls and keeps one stream. Saving a legacy multi-line channel replaces
  its lines with the displayed first stream, consistent with this single-line
  editor. No existing channel data was changed by deployment.
- Channel logo opens protected playback directly, without a chooser. Portrait
  start and manual Rotate are supported in the browser and Android player;
  iOS uses its orientation API. Physical-device rotation still requires testing.
