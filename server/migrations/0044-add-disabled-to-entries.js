module.exports = {
    async up(queryInterface, Sequelize) {
        const columns = await queryInterface.describeTable("entries");

        if (!columns.disabled) {
            await queryInterface.addColumn("entries", "disabled", {
                type: Sequelize.BOOLEAN,
                allowNull: false,
                defaultValue: false,
            });
        }
    },
};
