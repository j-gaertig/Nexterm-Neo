module.exports = {
    async up(queryInterface, Sequelize) {
        const tables = await queryInterface.showAllTables();
        if (!tables.includes("device_codes")) return;

        const columns = await queryInterface.describeTable("device_codes");
        if (columns.redeemedAt) return;

        await queryInterface.addColumn("device_codes", "redeemedAt", {
            type: Sequelize.DATE,
            allowNull: true,
        });
    },
};
