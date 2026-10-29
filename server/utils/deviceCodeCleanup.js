const { Op } = require("sequelize");
const DeviceCode = require("../models/DeviceCode");
const Session = require("../models/Session");
const logger = require("./logger");

const CODE_EXPIRY_MS = 10 * 60 * 1000;
const CODE_RETENTION_MS = 24 * 60 * 60 * 1000;
const CLEANUP_BATCH_SIZE = 500;

const getCodeCutoff = (now = Date.now()) => new Date(now - CODE_EXPIRY_MS);

// The conditional sessionId clear and the session delete share a transaction,
// so a concurrent redemption either wins the code row (and keeps its session)
// or observes the code as expired. A failure rolls the link back for retry.
const clearAndDestroySessions = async codes => {
    if (codes.length === 0) return 0;

    return DeviceCode.sequelize.transaction(async transaction => {
        const sessionIds = [];

        for (const deviceCode of codes) {
            const [cleared] = await DeviceCode.update(
                { sessionId: null },
                {
                    where: { id: deviceCode.id, sessionId: deviceCode.sessionId },
                    transaction,
                },
            );

            if (cleared > 0) sessionIds.push(deviceCode.sessionId);
        }

        if (sessionIds.length === 0) return 0;

        return Session.destroy({
            where: { id: { [Op.in]: sessionIds } },
            transaction,
        });
    });
};

const expireDeviceCode = async (deviceCode) => {
    if (!deviceCode.sessionId) return false;

    await clearAndDestroySessions([deviceCode]);
    return true;
};

const cleanupExpiredCodes = async (now = Date.now()) => {
    const expiryCutoff = getCodeCutoff(now);
    const retentionCutoff = new Date(now - CODE_RETENTION_MS);
    let removedCodes = 0;

    try {
        while (true) {
            const expiredAuthorizedCodes = await DeviceCode.findAll({
                where: {
                    createdAt: { [Op.lt]: expiryCutoff },
                    sessionId: { [Op.ne]: null },
                },
                attributes: ["id", "sessionId"],
                limit: CLEANUP_BATCH_SIZE,
            });
            if (expiredAuthorizedCodes.length === 0) break;

            const removedSessions = await clearAndDestroySessions(expiredAuthorizedCodes);
            if (removedSessions > 0) {
                logger.info("Removed sessions belonging to expired device codes", { count: removedSessions });
            }

            if (expiredAuthorizedCodes.length < CLEANUP_BATCH_SIZE) break;
        }
    } finally {
        // Only purge tombstones. Codes that still point at a session must never
        // be dropped before that session is gone, even if cleanup failed.
        removedCodes = await DeviceCode.destroy({
            where: {
                createdAt: { [Op.lt]: retentionCutoff },
                sessionId: null,
            },
        });
        if (removedCodes > 0) {
            logger.info("Removed expired device codes", { count: removedCodes });
        }
    }

    return removedCodes;
};

module.exports = {
    CODE_EXPIRY_MS,
    CODE_RETENTION_MS,
    CLEANUP_BATCH_SIZE,
    getCodeCutoff,
    expireDeviceCode,
    cleanupExpiredCodes,
};
