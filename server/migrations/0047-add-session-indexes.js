const INDEXES = [
    { name: "sessions_last_activity", fields: ["lastActivity"] },
    { name: "sessions_account_id_last_activity", fields: ["accountId", "lastActivity"] },
    { name: "sessions_token", fields: ["token"] },
];

module.exports = {
    async up(queryInterface) {
        const tables = await queryInterface.showAllTables();
        if (!tables.includes("sessions")) return;

        const existingIndexes = await queryInterface.showIndex("sessions");
        const existingNames = new Set(existingIndexes.map(index => index.name));

        for (const index of INDEXES) {
            if (existingNames.has(index.name)) continue;
            await queryInterface.addIndex("sessions", index.fields, { name: index.name });
        }
    },
};
