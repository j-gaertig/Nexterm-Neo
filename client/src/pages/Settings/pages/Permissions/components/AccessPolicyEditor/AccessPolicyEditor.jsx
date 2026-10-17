import "./styles.sass";
import { useMemo, useState } from "react";
import Icon from "@mdi/react";
import { mdiPlus, mdiClose } from "@mdi/js";
import Checkbox from "@/common/components/Checkbox";
import { useTranslation } from "react-i18next";

const MODES = ["disabled", "blacklist", "whitelist"];

const normalize = (policy) => ({
    ipMode: MODES.includes(policy?.ipMode) ? policy.ipMode : "disabled",
    ipRules: Array.isArray(policy?.ipRules) ? policy.ipRules : [],
    engineMode: MODES.includes(policy?.engineMode) ? policy.engineMode : "disabled",
    engineIds: Array.isArray(policy?.engineIds) ? policy.engineIds : [],
});

export const AccessPolicyEditor = ({ value, onChange, engines = [], inheritedRestricted = false }) => {
    const { t } = useTranslation();
    const policy = normalize(value);
    const [draft, setDraft] = useState("");
    const [engineDraft, setEngineDraft] = useState("");

    const set = (patch) => onChange({ ...policy, ...patch });

    const addRules = () => {
        const parts = draft.split(/[\n,;]+/).map((s) => s.trim()).filter(Boolean);
        if (!parts.length) return;
        const merged = [...policy.ipRules];
        for (const part of parts) {
            if (!merged.some((r) => r.toLowerCase() === part.toLowerCase())) merged.push(part);
        }
        set({ ipRules: merged.slice(0, 200) });
        setDraft("");
    };

    const removeRule = (rule) => set({ ipRules: policy.ipRules.filter((r) => r !== rule) });

    const toggleEngine = (id) => {
        const has = policy.engineIds.some((e) => (e === null ? id === null : Number(e) === Number(id)));
        set({
            engineIds: has
                ? policy.engineIds.filter((e) => !(e === null ? id === null : Number(e) === Number(id)))
                : [...policy.engineIds, id],
        });
    };

    const engineOptions = useMemo(() => {
        const opts = [{ id: null, name: t("settings.permissions.access.defaultEngine") }];
        for (const engine of engines) opts.push({ id: engine.id, name: engine.name, isLocal: engine.isLocal });
        return opts;
    }, [engines, t]);

    const knownEngineIds = useMemo(
        () => new Set(engineOptions.map((e) => (e.id === null ? "default" : Number(e.id)))),
        [engineOptions]);

    // Selected ids that are not in the known engine list (e.g. deleted engines,
    // or manual ids when the engine list could not be loaded). Always shown as
    // removable tags so they never become invisible dead weight.
    const extraEngineIds = policy.engineIds.filter((id) =>
        id !== null && !knownEngineIds.has(Number(id)));

    const addEngineId = (raw) => {
        const id = Number(raw);
        if (!Number.isInteger(id) || id <= 0) return;
        if (!policy.engineIds.some((e) => Number(e) === id)) set({ engineIds: [...policy.engineIds, id] });
        setEngineDraft("");
    };

    const removeEngineId = (id) => set({
        engineIds: policy.engineIds.filter((e) => !(e === null ? id === null : Number(e) === Number(id))),
    });

    const ipActive = policy.ipMode !== "disabled";
    const engineActive = policy.engineMode !== "disabled";

    return (
        <div className="access-policy-editor">
            <div className="ape-section">
                <div className="ape-section-head">
                    <h3>{t("settings.permissions.access.ipTitle")}</h3>
                </div>
                <div className="ape-modes">
                    {MODES.map((mode) => (
                        <button
                            key={mode}
                            type="button"
                            className={`ape-mode${policy.ipMode === mode ? " selected" : ""}`}
                            onClick={() => set({ ipMode: mode })}
                        >
                            {t(`settings.permissions.access.mode.${mode}`)}
                        </button>
                    ))}
                </div>

                {ipActive && (
                    <>
                        <div className="ape-add-row">
                            <input
                                type="text"
                                value={draft}
                                onChange={(e) => setDraft(e.target.value)}
                                onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); addRules(); } }}
                                placeholder={t("settings.permissions.access.ipPlaceholder")}
                            />
                            <button type="button" className="ape-add-btn" onClick={addRules} aria-label="add">
                                <Icon path={mdiPlus} />
                            </button>
                        </div>
                        {policy.ipRules.length > 0 ? (
                            <div className="ape-tags">
                                {policy.ipRules.map((rule) => (
                                    <span key={rule} className="ape-tag">
                                        {rule}
                                        <button type="button" onClick={() => removeRule(rule)} aria-label="remove">
                                            <Icon path={mdiClose} />
                                        </button>
                                    </span>
                                ))}
                            </div>
                        ) : (
                            <p className="empty">
                                {t(`settings.permissions.access.${policy.ipMode === "whitelist" ? "emptyRestricted" : "emptyAllowed"}`)}
                            </p>
                        )}
                    </>
                )}
            </div>

            <div className="ape-section">
                <div className="ape-section-head">
                    <h3>{t("settings.permissions.access.engineTitle")}</h3>
                </div>
                <div className="ape-modes">
                    {MODES.map((mode) => (
                        <button
                            key={mode}
                            type="button"
                            className={`ape-mode${policy.engineMode === mode ? " selected" : ""}`}
                            onClick={() => set({ engineMode: mode })}
                        >
                            {t(`settings.permissions.access.mode.${mode}`)}
                        </button>
                    ))}
                </div>

                {engineActive && (
                    <>
                        {engineOptions.length > 1 ? (
                            <div className="ape-engine-list">
                                {engineOptions.map((engine) => {
                                    const selected = policy.engineIds.some((e) =>
                                        (e === null ? engine.id === null : Number(e) === Number(engine.id)));
                                    return (
                                        <div
                                            key={engine.id === null ? "default" : engine.id}
                                            className={`ape-engine-item${selected ? " selected" : ""}`}
                                            onClick={() => toggleEngine(engine.id)}
                                        >
                                            <span className="ape-engine-name">
                                                {engine.name}
                                                {engine.isLocal ? ` (${t("settings.permissions.access.localEngine")})` : ""}
                                            </span>
                                            <span onClick={(e) => e.stopPropagation()}>
                                                <Checkbox
                                                    checked={selected}
                                                    onChange={() => toggleEngine(engine.id)}
                                                    id={`engine-${engine.id === null ? "default" : engine.id}`}
                                                />
                                            </span>
                                        </div>
                                    );
                                })}
                            </div>
                        ) : (
                            <>
                                <div
                                    className={`ape-engine-item${policy.engineIds.includes(null) ? " selected" : ""}`}
                                    onClick={() => toggleEngine(null)}
                                >
                                    <span className="ape-engine-name">
                                        {t("settings.permissions.access.defaultEngine")}
                                    </span>
                                    <span onClick={(e) => e.stopPropagation()}>
                                        <Checkbox
                                            checked={policy.engineIds.includes(null)}
                                            onChange={() => toggleEngine(null)}
                                            id="engine-default"
                                        />
                                    </span>
                                </div>
                                <div className="ape-add-row">
                                    <input
                                        type="text"
                                        inputMode="numeric"
                                        value={engineDraft}
                                        onChange={(e) => setEngineDraft(e.target.value)}
                                        placeholder={t("settings.permissions.access.engineIdPlaceholder")}
                                        onKeyDown={(e) => {
                                            if (e.key === "Enter") {
                                                e.preventDefault();
                                                addEngineId(e.target.value);
                                            }
                                        }}
                                    />
                                    <button type="button" className="ape-add-btn" onClick={() => addEngineId(engineDraft)} aria-label="add">
                                        <Icon path={mdiPlus} />
                                    </button>
                                </div>
                            </>
                        )}
                        {extraEngineIds.length > 0 && (
                            <div className="ape-tags">
                                {extraEngineIds.map((id) => (
                                    <span key={id} className="ape-tag">
                                        {t("settings.permissions.access.unknownEngine", { id })}
                                        <button type="button" onClick={() => removeEngineId(id)} aria-label="remove">
                                            <Icon path={mdiClose} />
                                        </button>
                                    </span>
                                ))}
                            </div>
                        )}
                        {policy.engineMode === "whitelist" && policy.engineIds.length === 0 && (
                            <p className="empty">{t("settings.permissions.access.emptyRestricted")}</p>
                        )}
                    </>
                )}
            </div>

            {inheritedRestricted && (
                <p className="ape-inherited-note">{t("settings.permissions.access.inheritedNote")}</p>
            )}
        </div>
    );
};
