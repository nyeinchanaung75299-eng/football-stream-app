# Channel logo images

Cached PNG, JPEG and WebP display images for the imported channel catalog. Filenames use content hashes so unchanged logos share one asset.

Sources: the supplied Shareext playlist at commit fab806521c1567e5acd5b6bff9b7be7a4a3735f4 and the public IPTV-org logo catalog (https://iptv-org.github.io/api/logos.json). The generic television image is from Twemoji (https://github.com/twitter/twemoji), CC-BY 4.0 graphics.

This directory contains display assets only. Channel stream URLs, DRM keys and license configuration are not stored here.

Named replacement images:

- `tnt-sports-1-uk.png` through `tnt-sports-4-uk.png`: channel-specific images from https://github.com/tv-logo/tv-logos/tree/main/countries/united-kingdom.
- `monomax-sports.png`: https://commons.wikimedia.org/wiki/File:MONOMAX_Sports_2026.svg (MONOMAX Sports, public-domain geometric/text logo).
- `thairath-tv.png`: https://commons.wikimedia.org/wiki/File:Thairath_TV32.svg (Netipikat, CC BY-SA 4.0).

These replace a shared LyngSat placeholder that was returned instead of the intended channel logos. The downloaded source images were checked visually as well as for valid image bytes.
