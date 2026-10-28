# PlayZ TV playlist reference review

Reviewed https://github.com/khadembd/playztv-playlist on 2026-10-28.

Useful integration patterns for this project:

- M3U import: channel name, logo and group from EXTINF metadata.
- Separate live/upcoming event lists and metadata JSON.
- Bounded concurrent checks, request deadlines and last-updated/verification status.
- Referer/Origin metadata mapping when a stream legitimately requires it.

The checked output/status.json reports zero events and zero streams. It explicitly
says events only, without channel/categories. It therefore provides no working
channel catalog to import at the time of review.

No explicit open-source LICENSE file was found. The README says its extracted
keys/APIs belong to PlayZ TV and stream URLs belong to their respective owners.
No source code, decryption keys or streams were copied into this project. Reuse
would require suitable permissions and verified availability. Keep TLS checks
enabled rather than copying the reference's disabled certificate verification.

The requested Channels grid and simple Live Links form are implemented
independently using this project's existing data and protected playback flow.
