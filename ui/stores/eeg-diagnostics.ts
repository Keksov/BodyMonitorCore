import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type {
  BodyMonitorEegDiagnosticsEvent,
  BodyMonitorOutputEvent,
  BodyMonitorPingResultEvent,
  EegDiagnosticsBleInfo,
  EegDiagnosticsComInfo,
} from '@protocol'

export type EegRuntimeConnectStage =
  | 'wait'
  | 'connect_attempt'
  | 'connect_fallback'
  | 'connect_failed'
  | 'connected'
  | 'disconnected'
  | 'reconnected'

export type EegDiagnosticsStatusKey =
  | 'hidden'
  | 'checking'
  | 'ready'
  | 'connected'
  | 'reconnected'
  | 'retrying'
  | 'stale'
  | 'offline'
  | 'com_missing'
  | 'ble_missing'
  | 'error'

export interface EegRuntimeState {
  readonly connectStage: EegRuntimeConnectStage | null
  readonly connectPort: string | null
  readonly connectErrorCode: number | null
  readonly connectAttempts: number
  readonly sdkVersion: number | null
  readonly poorSignal: number | null
  readonly lastEegSampleMs: number | null
  readonly isStale: boolean
}

export interface EegDeviceDiagnosticsState {
  readonly mac: string
  readonly diagnostics: BodyMonitorEegDiagnosticsEvent | null
  readonly pingResult: BodyMonitorPingResultEvent | null
  readonly runtime: EegRuntimeState
  readonly isLoading: boolean
  readonly lastCheckMs: number | null
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}

function normalizeMac(mac: string): string {
  return mac.trim().toLowerCase()
}

const STALE_THRESHOLD_MS = 10_000

export const useEegDiagnosticsStore = defineStore('eegDiagnostics', () => {
  const perMac = ref<Record<string, EegDeviceDiagnosticsState>>({})
  const loadingMacs = ref<Set<string>>(new Set())

  function ensureState(mac: string): EegDeviceDiagnosticsState {
    if (perMac.value[mac] === undefined) {
      perMac.value[mac] = {
        mac,
        diagnostics: null,
        pingResult: null,
        runtime: {
          connectStage: null,
          connectPort: null,
          connectErrorCode: null,
          connectAttempts: 0,
          sdkVersion: null,
          poorSignal: null,
          lastEegSampleMs: null,
          isStale: false,
        },
        isLoading: false,
        lastCheckMs: null,
      }
    }
    return perMac.value[mac]!
  }

  function setLoading(mac: string, loading: boolean): void {
    if (loading) {
      loadingMacs.value = new Set([...loadingMacs.value, mac])
    } else {
      const next = new Set(loadingMacs.value)
      next.delete(mac)
      loadingMacs.value = next
    }
    const existing = ensureState(mac)
    perMac.value[mac] = { ...existing, isLoading: loading }
  }

  function handleEegDiagnostics(event: BodyMonitorEegDiagnosticsEvent): void {
    const mac = normalizeMac(event.mac)
    const existing = ensureState(mac)
    setLoading(mac, false)
    perMac.value[mac] = {
      ...existing,
      diagnostics: event,
      isLoading: false,
      lastCheckMs: Date.now(),
    }
  }

  function handlePingResult(event: BodyMonitorPingResultEvent): void {
    const mac = normalizeMac(event.mac)
    const existing = ensureState(mac)
    perMac.value[mac] = { ...existing, pingResult: event }
  }

  function handleOutput(event: BodyMonitorOutputEvent): void {
    if (event.stream !== 'stdout') {
      return
    }

    const parsed = event.parsedJson
    if (!isRecord(parsed)) {
      return
    }

    const evtName = typeof parsed['event'] === 'string' ? parsed['event'] : ''
    const mac = typeof parsed['mac'] === 'string' ? normalizeMac(parsed['mac']) : null

    if (evtName === 'eeg_connect' && mac !== null) {
      const stage = typeof parsed['stage'] === 'string' ? (parsed['stage'] as EegRuntimeConnectStage) : null
      const port = typeof parsed['port'] === 'string' ? parsed['port'] : null
      const errorCode = typeof parsed['error_code'] === 'number' ? parsed['error_code'] : null

      const existing = ensureState(mac)
      const prevRuntime = existing.runtime

      let connectAttempts = prevRuntime.connectAttempts
      if (stage === 'connect_attempt' || stage === 'connect_fallback') {
        connectAttempts += 1
      } else if (stage === 'connected' || stage === 'reconnected' || stage === 'wait') {
        connectAttempts = 0
      }

      perMac.value[mac] = {
        ...existing,
        runtime: {
          ...prevRuntime,
          connectStage: stage ?? prevRuntime.connectStage,
          connectPort: port ?? prevRuntime.connectPort,
          connectErrorCode: errorCode ?? (stage === 'connected' || stage === 'reconnected' ? null : prevRuntime.connectErrorCode),
          connectAttempts,
          isStale: stage === 'disconnected' ? true : stage === 'connected' || stage === 'reconnected' ? false : prevRuntime.isStale,
        },
      }
    }

    if (evtName === 'eeg_init' && mac !== null) {
      const version = typeof parsed['version'] === 'number' ? parsed['version'] : null
      if (version !== null) {
        const existing = ensureState(mac)
        perMac.value[mac] = {
          ...existing,
          runtime: { ...existing.runtime, sdkVersion: version },
        }
      }
    }

    if ((evtName === 's' || parsed['e'] === 's') && mac !== null) {
      // Runtime EEG snapshot — track freshness
      const existing = ensureState(mac)
      const poorSignal = typeof parsed['ps'] === 'number' ? parsed['ps'] : existing.runtime.poorSignal
      perMac.value[mac] = {
        ...existing,
        runtime: {
          ...existing.runtime,
          poorSignal,
          lastEegSampleMs: Date.now(),
          isStale: false,
        },
      }
    }
  }

  function markLoading(mac: string): void {
    setLoading(normalizeMac(mac), true)
  }

  function getState(mac: string): EegDeviceDiagnosticsState {
    return ensureState(normalizeMac(mac))
  }

  function getStatusKey(mac: string): EegDiagnosticsStatusKey {
    const state = getState(mac)
    const stage = state.runtime.connectStage

    if (stage === 'connected' || stage === 'reconnected') {
      if (state.runtime.lastEegSampleMs !== null) {
        const ageMs = Date.now() - state.runtime.lastEegSampleMs
        if (ageMs > STALE_THRESHOLD_MS) {
          return 'stale'
        }
      }
      return stage === 'reconnected' ? 'reconnected' : 'connected'
    }

    if (stage === 'connect_attempt' || stage === 'connect_fallback' || stage === 'wait') {
      return 'retrying'
    }

    if (state.diagnostics !== null) {
      if (state.diagnostics.overallKey === 'ble_missing') return 'ble_missing'
      if (state.diagnostics.overallKey === 'com_missing') return 'com_missing'
      if (state.diagnostics.overallKey === 'error') return 'error'
    }

    if (stage === 'connect_failed' || stage === 'disconnected') {
      return 'offline'
    }

    if (state.diagnostics?.overallKey === 'ok') {
      return 'ready'
    }

    if (state.isLoading) {
      return 'checking'
    }

    if (stage === null && state.diagnostics === null && !state.isLoading) {
      return 'hidden'
    }

    return 'checking'
  }

  const allStates = computed(() => perMac.value)

  return {
    allStates,
    handleEegDiagnostics,
    handlePingResult,
    handleOutput,
    markLoading,
    getState,
    getStatusKey,
  }
})
