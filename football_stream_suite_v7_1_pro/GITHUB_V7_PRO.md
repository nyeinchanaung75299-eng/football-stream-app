# V7 Pro GitHub package

This ZIP is ready to upload to the GitHub repository root.

Included:
- admin_app/
- user_app/
- .github/workflows/build-apks.yml
- Supabase SQL/functions source for later deployment
- V7 Pro documentation

Important:
- Do not commit API_FOOTBALL_KEY, CRON_SECRET, service-role keys, or other private secrets.
- GitHub Actions builds split release APKs for Admin and Viewer.
- Supabase deployment/configuration can be completed separately.
