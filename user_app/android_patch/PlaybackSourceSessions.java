package com.example.football_viewer;

/** Holds one bounded late-backup update while the newest player is opening. */
public final class PlaybackSourceSessions {
    private static final int MAX_PENDING_CHARACTERS = 2 * 1024 * 1024;
    private String session;
    private boolean opening;
    private String pending;

    public synchronized void begin(String sessionId) {
        session = sessionId == null || sessionId.trim().isEmpty() ? null : sessionId;
        opening = session != null;
        pending = null;
    }

    public synchronized boolean isCurrent(String sessionId) {
        return session != null && session.equals(sessionId);
    }

    public synchronized boolean enqueueIfOpening(String sessionId, String payload) {
        if (!opening || !isCurrent(sessionId) || payload == null ||
                payload.length() > MAX_PENDING_CHARACTERS || payload.trim().isEmpty()) return false;
        // Updates contain the full append-only list. The newest snapshot also
        // contains every previous backup, so retaining one payload is enough.
        pending = payload;
        return true;
    }

    public synchronized String register(String sessionId) {
        if (!isCurrent(sessionId)) return null;
        opening = false;
        String snapshot = pending;
        pending = null;
        return snapshot;
    }

    public synchronized void close(String sessionId) {
        if (!isCurrent(sessionId)) return;
        session = null;
        opening = false;
        pending = null;
    }
}
