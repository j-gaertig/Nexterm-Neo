module.exports = {
    async up(queryInterface, Sequelize) {
        const { INTEGER, JSON, ENUM } = Sequelize;

        await queryInterface.createTable("group_access_policies", {
            groupId: {
                type: INTEGER,
                allowNull: false,
                primaryKey: true,
                references: { model: "permission_groups", key: "id" },
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
