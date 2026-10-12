module.exports = {
    async up(queryInterface, Sequelize) {
        const { INTEGER, JSON, ENUM } = Sequelize;

        await queryInterface.createTable("account_access_policies", {
            accountId: {
                type: INTEGER,
                allowNull: false,
                primaryKey: true,
                references: { model: "accounts", key: "id" },
                onDelete: "CASCADE",
            },
            ipMode: {
                type: ENUM("disabled", "blacklist", "whitelist"),
                allowNull: false,
                defaultValue: "disabled",
            },
            ipRules: {
                type: JSON,
                allowNull: false,
                defaultValue: [],
            },
            engineMode: {
                type: ENUM("disabled", "blacklist", "whitelist"),
                allowNull: false,
                defaultValue: "disabled",
            },
            engineIds: {
                type: JSON,
                allowNull: false,
                defaultValue: [],
            },
        });
    },
};
