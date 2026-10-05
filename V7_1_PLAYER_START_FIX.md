# V7.1 Pro player-start fix

- Makes Android 12 / OEM fullscreen setup non-fatal.
- Builds the player view hierarchy before immersive-mode calls.
- Starts playback only after the content view is attached.
- If startup still fails, the on-screen error now includes the exception class/message.
- Keeps server fallback and adaptive quality controls.
