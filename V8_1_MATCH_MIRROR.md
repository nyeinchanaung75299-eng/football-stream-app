# V8.1 VPN-free match-list mirror

Problem confirmed:
The Viewer can start normally, but on some networks the direct Supabase matches query
does not return until VPN is enabled.

V8.1 changes:
- Viewer tries Supabase first for fresh realtime data.
- If Supabase does not answer within 6 seconds, Viewer automatically loads the
  public match feed from the repository's dedicated `feed` branch.
- The feed includes the same public featured-match fields and active stream links
  already exposed to the Viewer.
- GitHub Actions refreshes the feed every 5 minutes from Supabase.
- Feed updates are pushed only to the `feed` branch, so they do not rebuild APKs.
- A small banner says when the app is using the mirror.
- Diagnostics now tests the GitHub mirror separately.

This is not a VPN bypass. It gives the public Viewer a second, independently hosted
read path for public match data when the Supabase hostname is unreachable from a
specific ISP/network.

Realtime:
- Direct Supabase mode keeps Realtime updates.
- Mirror mode can lag by up to roughly 5 minutes because GitHub Actions schedules
  are periodic and can occasionally start late.
