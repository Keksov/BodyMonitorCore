import { buildBodyMonitorCommandLine } from '../services/command-line'
import {
  capabilityCliParam,
  DEFAULT_BREATH_MAX_RR_MS,
  DEFAULT_BREATH_MIN_DELTA_MS,
  useDeviceStore,
} from '../stores/device'
import { useSessionStore } from '../stores/session'
import { useWs } from './use-ws'

export type MonitoringCapability = keyof typeof capabilityCliParam

const DEFAULT_MONITORING_CAPABILITIES = Object.keys(capabilityCliParam) as MonitoringCapability[]

export function useBodyMonitorSessionStarter() {
  const device = useDeviceStore()
  const session = useSessionStore()
  const ws = useWs()

  function resolveRequestedCapabilities(capabilities?: readonly MonitoringCapability[]): MonitoringCapability[] {
    if (capabilities === undefined) {
      return DEFAULT_MONITORING_CAPABILITIES.filter((capability) => {
        const mac = device.getSelectedMac(capability)
        return mac !== null && !device.isDeviceInactive(mac)
      })
    }

    return capabilities.filter((capability, index, entries) => {
      return capabilityCliParam[capability] !== undefined && entries.indexOf(capability) === index
    })
  }

  function buildStartParams(capabilities?: readonly MonitoringCapability[]): string[] | null {
    const requestedCapabilities = resolveRequestedCapabilities(capabilities)
    if (requestedCapabilities.length === 0) {
      return null
    }

    const params: string[] = []

    for (const capability of requestedCapabilities) {
      const mac = device.getConnectableMac(capability)
      if (mac === null) {
        return null
      }

      params.push(`${capabilityCliParam[capability]}=${mac}`)
    }

    if (requestedCapabilities.includes('ecg')) {
      const ecgMac = device.getConnectableMac('ecg')
      if (ecgMac !== null) {
        const breathSettings = device.getBreathSettings(ecgMac)
        if (breathSettings.enabled) {
          params.push('--breath')
          if (breathSettings.minDeltaMs !== DEFAULT_BREATH_MIN_DELTA_MS) {
            params.push(`--breath-min-delta=${breathSettings.minDeltaMs}`)
          }
          if (breathSettings.maxRrMs !== DEFAULT_BREATH_MAX_RR_MS) {
            params.push(`--breath-rr-max=${breathSettings.maxRrMs}`)
          }
        }
      }
    }

    if (requestedCapabilities.includes('eeg')) {
      const eegMac = device.getConnectableMac('eeg')
      if (eegMac !== null) {
        params.push(`--eeg-stale-sec=${device.getEegStaleSec(eegMac)}`)
      }
    }

    params.push('--log-format=jsonl')
    return params
  }

  function startMonitoring(capabilities?: readonly MonitoringCapability[]): boolean {
    if (ws.connectionState.value !== 'connected') {
      return false
    }

    const params = buildStartParams(capabilities)
    if (params === null) {
      return false
    }

    session.resetOutputState()
    session.beginConnect(buildBodyMonitorCommandLine(params))
    ws.send({ type: 'bodymonitor_stdio_configure', params })
    ws.send({ type: 'bodymonitor_stdio_start' })
    return true
  }

  return {
    buildStartParams,
    startMonitoring,
  }
}