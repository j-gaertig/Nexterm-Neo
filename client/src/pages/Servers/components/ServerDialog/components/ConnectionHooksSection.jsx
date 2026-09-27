import { useEffect, useState } from "react";
import Icon from "@mdi/react";
import { mdiLogin, mdiLogout, mdiSwapVertical } from "@mdi/js";
import { useTranslation } from "react-i18next";
import { getRequest } from "@/common/utils/RequestUtil.js";

const HookGroup = ({ icon, title, description, steps, onStepsChange, values, onValueChange, placeholders, engineHint, localTarget, onLocalTargetChange, hostBridgeAvailable }) => {
    const { t } = useTranslation();

    const swapSteps = () => {
        if (steps.length < 2) return;
        onStepsChange([...steps].reverse());
    };

    return (
        <div className="jump-hosts-section">
            <div className="jump-hosts-header">
                <div className="jump-hosts-info">
                    <span className="jump-hosts-label">
                        <Icon path={icon} size={0.8} style={{ marginRight: '8px', verticalAlign: 'middle' }} />
                        {title}
                    </span>
                    <span className="jump-hosts-description">
                        {description}
                    </span>
                </div>
            </div>

            <div className="hook-reorder">
                <button
                    type="button"
                    className="hook-swap-btn"
                    title={t('servers.dialog.settings.hooks.swapTooltip')}
                    aria-label={t('servers.dialog.settings.hooks.swapTooltip')}
                    onClick={swapSteps}
                >
                    <Icon path={mdiSwapVertical} size={0.9} />
                </button>
                <div className="hook-list">
                    {steps.map((step) => (
                        <div key={step} className="hook-item">
                            <span className={`hook-badge hook-badge--${step}`}>
                                {step === 'local'
                                    ? t(localTarget === 'docker-host' ? 'servers.dialog.settings.hooks.dockerHostBadge' : 'servers.dialog.settings.hooks.localBadge')
                                    : t('servers.dialog.settings.hooks.remoteBadge')}
                            </span>
                            <div className="hook-input">
                                {step === 'local' && (
                                    <select
                                        className="hook-target-select"
                                        aria-label={t('servers.dialog.settings.hooks.localTargetLabel')}
                                        value={localTarget}
                                        onChange={(e) => onLocalTargetChange(e.target.value)}
                                    >
                                        <option value="engine">{t('servers.dialog.settings.hooks.localTargetEngine')}</option>
                                        <option value="docker-host">{t('servers.dialog.settings.hooks.localTargetDockerHost')}</option>
                                    </select>
                                )}
                                <input
                                    type="text"
                                    className="hook-textarea"
                                    spellCheck={false}
                                    maxLength={2000}
                                    aria-label={`${title} - ${step === 'local'
                                        ? t(localTarget === 'docker-host' ? 'servers.dialog.settings.hooks.dockerHostBadge' : 'servers.dialog.settings.hooks.localBadge')
                                        : t('servers.dialog.settings.hooks.remoteBadge')}`}
                                    value={values[step] || ""}
                                    placeholder={placeholders[step]}
                                    onChange={(e) => onValueChange(step, e.target.value)}
                                />
                            </div>
                        </div>
                    ))}
                </div>
            </div>

            {engineHint && <p className="hook-engine-hint">{engineHint}</p>}
            {localTarget === 'docker-host' && (
                <p className="hook-engine-hint">
                    {hostBridgeAvailable
                        ? t('servers.dialog.settings.hooks.dockerHostRootHint')
                        : t('servers.dialog.settings.hooks.dockerHostUnavailableHint')}
                </p>
            )}
        </div>
    );
};

const ConnectionHooksSection = ({ config, setConfig }) => {
    const { t } = useTranslation();
    const [engines, setEngines] = useState([]);
    const [hostBridgeAvailable, setHostBridgeAvailable] = useState(false);

    useEffect(() => {
        getRequest("engines").then(data => setEngines(data || [])).catch(() => {});
        getRequest("entries/host-exec-bridge").then(data => setHostBridgeAvailable(data?.available === true)).catch(() => setHostBridgeAvailable(false));
    }, []);

    const updateConfig = (key, value) => {
        setConfig(prev => ({ ...prev, [key]: value }));
    };

    const hasEngineId = !!config?.engineId;
    const selectedEngine = hasEngineId
        ? engines.find(e => String(e.id) === String(config.engineId))
        : engines[0];
    const engineOffline = hasEngineId && (!selectedEngine || selectedEngine.connected === false);
    const engineHint = engineOffline
        ? t('servers.dialog.settings.hooks.unknownEngineHint', { engine: config.engineId })
        : null;

    const orderToSteps = (order, defaultFirst) => {
        if (order === 'remote-first') return ['remote', 'local'];
        if (order === 'local-first') return ['local', 'remote'];
        return defaultFirst === 'remote' ? ['remote', 'local'] : ['local', 'remote'];
    };
    const stepsToOrder = (steps) => steps[0] === 'remote' ? 'remote-first' : 'local-first';

    return (
        <>
            <HookGroup
                icon={mdiLogin}
                title={t('servers.dialog.settings.hooks.pre.title')}
                description={t('servers.dialog.settings.hooks.pre.description')}
                steps={orderToSteps(config?.preOrder, 'local')}
                onStepsChange={(steps) => updateConfig('preOrder', stepsToOrder(steps))}
                values={{ local: config?.preLocalCommand || "", remote: config?.preRemoteCommand || "" }}
                onValueChange={(step, value) => updateConfig(step === 'local' ? 'preLocalCommand' : 'preRemoteCommand', value)}
                placeholders={{ local: t((config?.preLocalTarget || 'engine') === 'docker-host' ? 'servers.dialog.settings.hooks.dockerHostHint' : 'servers.dialog.settings.hooks.localHint'), remote: t('servers.dialog.settings.hooks.remoteHint') }}
                localTarget={config?.preLocalTarget || 'engine'}
                onLocalTargetChange={(value) => updateConfig('preLocalTarget', value)}
                engineHint={(config?.preLocalTarget || 'engine') === 'engine' ? engineHint : null}
                hostBridgeAvailable={hostBridgeAvailable}
            />
            <HookGroup
                icon={mdiLogout}
                title={t('servers.dialog.settings.hooks.after.title')}
                description={t('servers.dialog.settings.hooks.after.description')}
                steps={orderToSteps(config?.afterOrder, 'remote')}
                onStepsChange={(steps) => updateConfig('afterOrder', stepsToOrder(steps))}
                values={{ local: config?.afterLocalCommand || "", remote: config?.afterRemoteCommand || "" }}
                onValueChange={(step, value) => updateConfig(step === 'local' ? 'afterLocalCommand' : 'afterRemoteCommand', value)}
                placeholders={{ local: t((config?.afterLocalTarget || 'engine') === 'docker-host' ? 'servers.dialog.settings.hooks.dockerHostHint' : 'servers.dialog.settings.hooks.localHint'), remote: t('servers.dialog.settings.hooks.remoteHint') }}
                localTarget={config?.afterLocalTarget || 'engine'}
                onLocalTargetChange={(value) => updateConfig('afterLocalTarget', value)}
                engineHint={(config?.afterLocalTarget || 'engine') === 'engine' ? engineHint : null}
                hostBridgeAvailable={hostBridgeAvailable}
            />
        </>
    );
};

export default ConnectionHooksSection;
