// Public BotFather command descriptions only. Never include tokens or credentials.
// setMyCommands exposes these under Telegram's native /commands menu.
export const BOT_COMMANDS = Object.freeze({
  viewer: [
    {command:"start",description:"Open NCA Viewer menu"},
    {command:"menu",description:"Show all Viewer buttons"},
    {command:"today",description:"Today's football matches"},
    {command:"live",description:"Live football matches"},
    {command:"schedule",description:"Upcoming football schedule"},
    {command:"channels",description:"Available channels"},
    {command:"reminders",description:"My match reminders"},
    {command:"unsubscribe",description:"Cancel all reminders"},
    {command:"apk",description:"Download verified Viewer APK"},
    {command:"build",description:"Check recent build status"},
    {command:"help",description:"Viewer commands and help"},
  ],
  admin: [
    {command:"start",description:"Open private Admin menu"},
    {command:"menu",description:"Show private Admin buttons"},
    {command:"tools",description:"Admin tools"},
    {command:"whoami",description:"Find your own Telegram ID"},
    {command:"channels",description:"Browse channels"},
    {command:"health",description:"Channel health summary"},
    {command:"build",description:"Check recent builds"},
    {command:"apk",description:"Choose Viewer or Admin APK"},
    {command:"apk_viewer",description:"Download Viewer APK"},
    {command:"apk_admin",description:"Download Admin APK"},
  ],
});
