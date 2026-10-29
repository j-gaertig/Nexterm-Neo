const Session = require("../models/Session");
const { isSessionExpired, teardownLoginSession } = require("./sessionCleanup");
const logger = require("./logger");

const ACTIVITY_TOUCH_INTERVAL_MS = 5 * 60 * 1000;
const MAX_TRACKED_SESSIONS = 10000;
const lastTouches = new Map();

const forgetSession = sessionId => lastTouches.delete(sessionId);

const findActiveSession = async token => {
    if (!token) return null;

    const session = await Session.findOne({ where: { token } });
    if (!session) return null;

    if (isSessionExpired(session.lastActivity)) {
        await Session.destroy({ where: { id: session.id } });

        try {
            await teardownLoginSession(session.id);
        } catch (error) {
            logger.warn("Failed to tear down expired login session", { sessionId: session.id, error: error.message });
        }

        return null;
    }

    return session;
};

const touchSession = (sessionId, now = Date.now()) => {
    if (sessionId === null || sessionId === undefined) return;

    const lastTouch = lastTouches.get(sessionId) || 0;
    if (now - lastTouch < ACTIVITY_TOUCH_INTERVAL_MS) return;

    if (!lastTouches.has(sessionId) && lastTouches.size >= MAX_TRACKED_SESSIONS) {
        const oldestSessionId = lastTouches.keys().next().value;
        lastTouches.delete(oldestSessionId);
    }

    lastTouches.set(sessionId, now);

    Session.update({ lastActivity: new Date(now) }, { where: { id: sessionId } })
        .catch(error => logger.debug("Failed to update login session activity", { sessionId, error: error.message }));
};

module.exports = {
    ACTIVITY_TOUCH_INTERVAL_MS,
    MAX_TRACKED_SESSIONS,
    forgetSession,
    findActiveSession,
    touchSession,
};
