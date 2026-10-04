# V6.2 Clean Admin

## Live link screen
The normal screen now shows only:
- Match
- Server name
- Stream type
- Stream URL
- Add Server

Less-used fields are inside **Advanced options**:
- Referer
- Origin
- ClearKey keyID/keyData
- WebView

Player notification was removed from the admin form.

## Headers
For native HLS / DASH / FLV / MP4 / direct playback:
- Referer is sent as an HTTP request header when provided.
- Origin is sent as an HTTP request header when provided.

For WebView:
- Referer/Origin are supplied to the initial page request.
- A website can still control or replace headers on later subrequests.

## Edit / delete
### Stream links
Select a match in Live Links. Existing servers are shown below.
Each server has:
- Edit
- Delete
- Active / inactive

A wrong URL, header, stream type, ClearKey or WebView URL can be corrected without recreating the match.

### Match details
Manage Matches now lets you edit:
- League
- Home team
- Away team
- Home logo URL
- Away logo URL
- Date
- Time
- Display order
- LIVE status
- Active/hidden status

The same menu also opens **Manage links** for that match or deletes the whole match.
