const Sequelize = require("sequelize");
const db = require("../utils/database");

module.exports = db.define("group_access_policies", {
    groupId: {
        type: Sequelize.INTEGER,
        allowNull: false,
        primaryKey: true,
        references: {
            model: "permission_groups",
            key: "id",
        },
        onDelete: "CASCADE",
    },
    ipMode: {
        type: Sequelize.ENUM("disabled", "blacklist", "whitelist"),
        allowNull: false,
        defaultValue: "disabled",
    },
    ipRules: {
        type: Sequelize.JSON,
        allowNull: false,
        defaultValue: [],
    },
    engineMode: {
        type: Sequelize.ENUM("disabled", "blacklist", "whitelist"),
        allowNull: false,
        defaultValue: "disabled",
    },
    engineIds: {
        type: Sequelize.JSON,
        allowNull: false,
        defaultValue: [],
    },
}, {
    freezeTableName: true,
    createdAt: false,
    updatedAt: false,
    hooks: {
        afterFind: (rows) => {
            const parse = (row) => {
                if (!row) return;
                for (const key of ["ipRules", "engineIds"]) {
                    if (typeof row[key] === "string") {
                        try {
                            row[key] = JSON.parse(row[key]);
                        } catch {
                            row[key] = [];
                        }
                    }
                    if (!Array.isArray(row[key])) row[key] = [];
                }
            };
            if (Array.isArray(rows)) rows.forEach(parse);
            else parse(rows);
        },
    },
});
