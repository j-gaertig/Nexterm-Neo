const { Op } = require("sequelize");
const Session = require("../models/Session");
const { cleanupExpiredCodes } = require("./deviceCodeCleanup");
const logger = require("./logger");

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const DEFAULT_RETENTION_DAYS = 30;
const MAX_RETENTION_DAYS = 36500;
const CLEANUP_INTERVAL_MS = 60 * 60 * 1000;
const CLEANUP_BATCH_SIZE = 500;

let cleanupTimer = null;
let cleanupPromise = null;
let lifecycle = Promise.resolve();

const parseRetentionDays = value => {
    const days = Number(value);

    return Number.isSafeInteger(days) && days > 0 && days <= MAX_RETENTION_DAYS
        ? days
        : DEFAULT_RETENTION_DAYS;
};

const getRetentionDays = (value = process.env.SESSION_RETENTION_DAYS) => parseRetentionDays(value);

const getSessionRetentionCutoff = (now = Date.now(), value = process.env.SESSION_RETENTION_DAYS) => {
    const cutoff = new Date(now - getRetentionDays(value) * MS_PER_DAY);

    return Number.isFinite(cutoff.getTime()) ? cutoff : new Date(now - DEFAULT_RETENTION_DAYS * MS_PER_DAY);
};

const isSessionExpired = (lastActivity, now = Date.now()) => {
    const lastActivityTime = new Date(lastActivity).getTime();

    return !Number.isFinite(lastActivityTime) || lastActivityTime < getSessionRetentionCutoff(now).getTime();
};

const teardownLoginSession = async sessionId => {
    const stateBroadcaster = require("../lib/StateBroadcaster");
    const SessionManager = require("../lib/SessionManager");
    const { forgetSession } = require("./sessionActivity");

    stateBroadcaster.forceLogoutSession(sessionId);
    forgetSession(sessionId);
    SessionManager.disconnectAuthSessionViewers(sessionId);
    await SessionManager.removeAllByAuthSessionId(sessionId);
};

const teardownSessions = async sessionIds => {
    for (const id of sessionIds) {
        try {
            await teardownLoginSession(id);
        } catch (error) {
            logger.warn("Failed to tear down expired login session", { sessionId: id, error: error.message });
        }
    }
};

const cleanupInactiveSessions = async ({ now = Date.now(), retentionDays, SessionModel = Session } = {}) => {
    const cutoff = getSessionRetentionCutoff(now, retentionDays);
    const where = {
        [Op.or]: [
            { lastActivity: { [Op.lt]: cutoff } },
            { lastActivity: null },
        ],
    };

    let removedSessions = 0;

    while (true) {
        const staleSessions = await SessionModel.findAll({ where, attributes: ["id"], limit: CLEANUP_BATCH_SIZE });
        if (staleSessions.length === 0) break;

        const ids = staleSessions.map(session => session.id);
        // Only tear down rows that are confirmed gone. If the delete or the
        // survivor reconciliation fails, skip teardown entirely so an active
        // session is never killed because of a stale snapshot.
        let deletedIds = [];

        try {
            await SessionModel.destroy({ where: { id: { [Op.in]: ids }, ...where } });

            const survivors = await SessionModel.findAll({
                where: { id: { [Op.in]: ids } },
                attributes: ["id"],
            });
            const survivorIds = new Set(survivors.map(session => session.id));
            deletedIds = ids.filter(id => !survivorIds.has(id));
        } finally {
            removedSessions += deletedIds.length;
            await teardownSessions(deletedIds);
        }

        if (staleSessions.length < CLEANUP_BATCH_SIZE) break;
    }

    if (removedSessions > 0) {
        logger.info("Removed inactive login sessions", {
            count: removedSessions,
            retentionDays: getRetentionDays(retentionDays),
        });
    }

    return removedSessions;
};

const runCleanup = async () => {
    if (cleanupPromise) return cleanupPromise;

    cleanupPromise = (async () => {
        try {
            await cleanupExpiredCodes();
        } catch (error) {
            logger.error("Failed to clean up expired device codes", { error: error.message });
        }

        try {
            await cleanupInactiveSessions();
        } catch (error) {
            logger.error("Failed to clean up inactive login sessions", { error: error.message });
        }
    })();

    try {
        await cleanupPromise;
    } finally {
        cleanupPromise = null;
    }
};

// Start and stop are serialized so a start/stop/start sequence cannot leave the
// cleaner stopped while start() reports success.
const enqueueLifecycle = operation => {
    const result = lifecycle.then(operation, operation);
    lifecycle = result.then(() => undefined, () => undefined);
    return result;
};

const startNow = async ({ intervalMs }) => {
    if (cleanupTimer !== null) return;

    await runCleanup();

    if (cleanupTimer !== null) return;

    cleanupTimer = setInterval(runCleanup, intervalMs);
    if (typeof cleanupTimer.unref === "function") cleanupTimer.unref();

    logger.system(`Session cleanup started (retention: ${getRetentionDays()} days)`);
};

const start = ({ intervalMs = CLEANUP_INTERVAL_MS } = {}) => enqueueLifecycle(() => startNow({ intervalMs }));

const stop = () => enqueueLifecycle(async () => {
    if (cleanupTimer !== null) {
        clearInterval(cleanupTimer);
        cleanupTimer = null;
    }

    if (cleanupPromise) await cleanupPromise;
});

const isRunning = () => cleanupTimer !== null;

module.exports = {
    MS_PER_DAY,
    DEFAULT_RETENTION_DAYS,
    MAX_RETENTION_DAYS,
    CLEANUP_INTERVAL_MS,
    CLEANUP_BATCH_SIZE,
    parseRetentionDays,
    getRetentionDays,
    getSessionRetentionCutoff,
    isSessionExpired,
    teardownLoginSession,
    cleanupInactiveSessions,
    runCleanup,
    start,
    stop,
    isRunning,
};
