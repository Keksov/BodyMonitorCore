import { defineStore } from 'pinia'
import { computed, ref, watch } from 'vue'
import type {
  DeviceInfo,
  BodyMonitorDeviceEvent,
  BodyMonitorDevicesEvent,
  BodyMonitorPingResultEvent,
  BodyMonitorScanDeviceStatusEvent,
  BodyMonitorScanDeviceStage,
} from '@protocol'

export type DevicePingState = 'idle' | 'pinging' | 'reachable' | 'unreachable'

export type DeviceScanProbeState = BodyMonitorScanDeviceStage

interface DevicePingStatus {
  readonly state: DevicePingState
  readonly lastAttemptMs: number | null
  readonly lastSuccessMs: number | null
  readonly identifier?: string
  readonly message?: string
}

export interface DeviceScanProbeStatus {
  readonly state: DeviceScanProbeState
  readonly totalCount: number
  readonly completedCount: number
  readonly message?: string
}

export interface BreathSettings {
  readonly enabled: boolean
  readonly minDeltaMs: number
  readonly maxRrMs: number
}

export type CalibrationActivityId = 'attention' | 'alphaRelaxation' | 'drowse'

export const EEG_BAND_KEYS = [
  'delta',
  'theta',
  'alpha1',
  'alpha2',
  'beta1',
  'beta2',
  'gamma1',
  'gamma2',
] as const

export type EegBandKey = (typeof EEG_BAND_KEYS)[number]

export const EEG_CALIBRATION_WARMUP_SEC = 15
export const EEG_CALIBRATION_MIN_ACCEPTED_SAMPLES = 30

export interface EegBandRange {
  readonly min: number
  readonly max: number
}

export type EegBandRangeMap = Record<EegBandKey, EegBandRange>

export interface EegCalibrationModeStats {
  readonly version: 1
  readonly activityId: CalibrationActivityId
  readonly recordedAtMs: number
  readonly durationSec: number
  readonly acceptedSampleCount: number
  readonly bandRanges: EegBandRangeMap
}

export interface EegCalibrationProfile {
  readonly version: 1
  readonly recordedAtMs: number
  readonly modeStats: Partial<Record<CalibrationActivityId, EegCalibrationModeStats>>
  readonly completedModes: Record<CalibrationActivityId, boolean>
  readonly deviceWideMin: Record<EegBandKey, number>
  readonly deviceWideMax: Record<EegBandKey, number>
  readonly invalidBands: readonly EegBandKey[]
  readonly isComplete: boolean
  readonly capturePolicy: {
    readonly warmupSec: number
    readonly requiresPoorSignalZero: boolean
    readonly minAcceptedSamples: number
  }
  readonly deltaCaveat: boolean
}

export interface AttentionCalibrationSummary {
  readonly version: 1
  readonly activityId: 'attention'
  readonly recordedAtMs: number
  readonly durationSec: number
  readonly completedTargetCount: number
  readonly errorCount: number
}

export interface AlphaRelaxationSummary {
  readonly version: 1
  readonly activityId: 'alphaRelaxation'
  readonly recordedAtMs: number
  readonly durationSec: number
  readonly cyclesCompleted: number
}

export interface DrowseCalibrationSummary {
  readonly version: 1
  readonly activityId: 'drowse'
  readonly recordedAtMs: number
  readonly durationSec: number
}

export interface DeviceCalibrationSummary {
  readonly attention?: AttentionCalibrationSummary
  readonly alphaRelaxation?: AlphaRelaxationSummary
  readonly drowse?: DrowseCalibrationSummary
  readonly eegProfile?: EegCalibrationProfile
}

/** Capability display metadata: icon name, icon color */
export const capabilityMeta: Record<string, { icon: string; color: string }> = {
  eeg: { icon: 'psychology', color: 'blue-4' },
  ecg: { icon: 'favorite', color: 'red-4' },
  blood_pressure: { icon: 'speed', color: 'green-4' },
}

/** Maps capability id to BodyMonitor CLI parameter name */
export const capabilityCliParam: Record<string, string> = {
  eeg: '--eeg',
  ecg: '--ecg',
}

const selectableCapabilities = Object.keys(capabilityCliParam)
const selectableCapabilitySet = new Set(selectableCapabilities)

export const DEFAULT_BREATH_MIN_DELTA_MS = 3.0
export const DEFAULT_BREATH_MAX_RR_MS = 1300.0
export const DEFAULT_CONNECT_TIMEOUT_SEC = 60
export const DEFAULT_EEG_STALE_SEC = 10

const DEFAULT_BREATH_SETTINGS: BreathSettings = {
  enabled: false,
  minDeltaMs: DEFAULT_BREATH_MIN_DELTA_MS,
  maxRrMs: DEFAULT_BREATH_MAX_RR_MS,
}

const MIN_VALID_MAX_RR_MS = 300
const CALIBRATION_ACTIVITY_IDS: readonly CalibrationActivityId[] = ['attention', 'alphaRelaxation', 'drowse']

const DEFAULT_EEG_CAPTURE_POLICY = {
  warmupSec: EEG_CALIBRATION_WARMUP_SEC,
  requiresPoorSignalZero: true,
  minAcceptedSamples: EEG_CALIBRATION_MIN_ACCEPTED_SAMPLES,
} as const

const STORAGE_FOUND_DEVICES = 'mw_devices'
const STORAGE_MARKED_DEVICES = 'mw_markedDevices'
// This key intentionally changed to drop stale auto-generated inactive state.
// Only explicit user "do not connect" choices should persist here.
const STORAGE_INACTIVE_DEVICES = 'mw_userInactiveDevices'
const STORAGE_COLLAPSED_DEVICES = 'mw_collapsedDevices'
const STORAGE_SELECTION = 'mw_selectedDevices'
const STORAGE_BREATH_SETTINGS = 'mw_breathSettings'
const STORAGE_CONNECT_TIMEOUTS = 'mw_connectTimeoutSecByDevice'
const STORAGE_EEG_STALE_SEC = 'mw_eegStaleSecByDevice'
const STORAGE_CALIBRATION_SUMMARIES = 'mw_calibrationSummariesByDevice'

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === 'object' && value !== null
}

const parsePositiveNumber = (value: unknown, fallback: number): number => {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback
  }

  return parsed
}

const parseNumberAbove = (value: unknown, threshold: number, fallback: number): number => {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed <= threshold) {
    return fallback
  }

  return parsed
}

const normalizeMacAddress = (value: string): string | null => {
  const normalized = value.trim().toLowerCase()
  return normalized === '' ? null : normalized
}

const sanitizeBreathSettings = (value: unknown): BreathSettings => {
  if (!isRecord(value)) {
    return { ...DEFAULT_BREATH_SETTINGS }
  }

  return {
    enabled: typeof value.enabled === 'boolean' ? value.enabled : DEFAULT_BREATH_SETTINGS.enabled,
    minDeltaMs: parsePositiveNumber(value.minDeltaMs, DEFAULT_BREATH_SETTINGS.minDeltaMs),
    maxRrMs: parseNumberAbove(value.maxRrMs, MIN_VALID_MAX_RR_MS, DEFAULT_BREATH_SETTINGS.maxRrMs),
  }
}

const sanitizeBreathSettingsMap = (value: unknown): Record<string, BreathSettings> => {
  if (!isRecord(value)) {
    return {}
  }

  const result: Record<string, BreathSettings> = {}
  for (const [mac, settings] of Object.entries(value)) {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      continue
    }

    result[normalizedMac] = sanitizeBreathSettings(settings)
  }

  return result
}

const sanitizeNonNegativeInteger = (value: unknown, fallback = 0): number => {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 0) {
    return fallback
  }

  return Math.trunc(parsed)
}

const sanitizeTimestampMs = (value: unknown): number | null => {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null
  }

  return Math.trunc(parsed)
}

const sanitizeFiniteNumber = (value: unknown): number | null => {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  return Number.isFinite(parsed) ? parsed : null
}

const sanitizeAttentionCalibrationSummary = (value: unknown): AttentionCalibrationSummary | null => {
  if (!isRecord(value)) {
    return null
  }

  const recordedAtMs = sanitizeTimestampMs(value.recordedAtMs)
  if (recordedAtMs === null) {
    return null
  }

  return {
    version: 1,
    activityId: 'attention',
    recordedAtMs,
    durationSec: Math.max(1, sanitizeNonNegativeInteger(value.durationSec, 60)),
    completedTargetCount: sanitizeNonNegativeInteger(value.completedTargetCount),
    errorCount: sanitizeNonNegativeInteger(value.errorCount),
  }
}

const sanitizeAlphaRelaxationSummary = (value: unknown): AlphaRelaxationSummary | null => {
  if (!isRecord(value)) {
    return null
  }

  const recordedAtMs = sanitizeTimestampMs(value.recordedAtMs)
  if (recordedAtMs === null) {
    return null
  }

  return {
    version: 1,
    activityId: 'alphaRelaxation',
    recordedAtMs,
    durationSec: Math.max(1, sanitizeNonNegativeInteger(value.durationSec, 60)),
    cyclesCompleted: Math.max(1, sanitizeNonNegativeInteger(value.cyclesCompleted, 6)),
  }
}

const sanitizeDrowseCalibrationSummary = (value: unknown): DrowseCalibrationSummary | null => {
  if (!isRecord(value)) {
    return null
  }

  const recordedAtMs = sanitizeTimestampMs(value.recordedAtMs)
  if (recordedAtMs === null) {
    return null
  }

  return {
    version: 1,
    activityId: 'drowse',
    recordedAtMs,
    durationSec: Math.max(1, sanitizeNonNegativeInteger(value.durationSec, 60)),
  }
}

const sanitizeEegBandRangeMap = (value: unknown): EegBandRangeMap | null => {
  if (!isRecord(value)) {
    return null
  }

  const bandRanges: Partial<EegBandRangeMap> = {}
  for (const bandKey of EEG_BAND_KEYS) {
    const bandValue = value[bandKey]
    if (!isRecord(bandValue)) {
      return null
    }

    const minValue = sanitizeFiniteNumber(bandValue.min)
    const maxValue = sanitizeFiniteNumber(bandValue.max)
    if (minValue === null || maxValue === null) {
      return null
    }

    bandRanges[bandKey] = {
      min: minValue,
      max: maxValue,
    }
  }

  return bandRanges as EegBandRangeMap
}

const sanitizeEegCalibrationModeStats = (
  value: unknown,
  activityId: CalibrationActivityId,
): EegCalibrationModeStats | null => {
  if (!isRecord(value)) {
    return null
  }

  const recordedAtMs = sanitizeTimestampMs(value.recordedAtMs)
  if (recordedAtMs === null) {
    return null
  }

  const bandRanges = sanitizeEegBandRangeMap(value.bandRanges)
  if (bandRanges === null) {
    return null
  }

  return {
    version: 1,
    activityId,
    recordedAtMs,
    durationSec: Math.max(1, sanitizeNonNegativeInteger(value.durationSec, 60)),
    acceptedSampleCount: sanitizeNonNegativeInteger(value.acceptedSampleCount),
    bandRanges,
  }
}

const buildEegCalibrationProfile = (
  modeStats: Partial<Record<CalibrationActivityId, EegCalibrationModeStats>>,
  recordedAtMsOverride?: number,
): EegCalibrationProfile => {
  const completedModes: Record<CalibrationActivityId, boolean> = {
    attention: modeStats.attention !== undefined,
    alphaRelaxation: modeStats.alphaRelaxation !== undefined,
    drowse: modeStats.drowse !== undefined,
  }

  const accumulatedMin = Object.fromEntries(
    EEG_BAND_KEYS.map((bandKey) => [bandKey, Number.POSITIVE_INFINITY]),
  ) as Record<EegBandKey, number>
  const accumulatedMax = Object.fromEntries(
    EEG_BAND_KEYS.map((bandKey) => [bandKey, Number.NEGATIVE_INFINITY]),
  ) as Record<EegBandKey, number>

  for (const activityId of CALIBRATION_ACTIVITY_IDS) {
    const activityStats = modeStats[activityId]
    if (activityStats === undefined) {
      continue
    }

    for (const bandKey of EEG_BAND_KEYS) {
      const bandRange = activityStats.bandRanges[bandKey]
      accumulatedMin[bandKey] = Math.min(accumulatedMin[bandKey], bandRange.min)
      accumulatedMax[bandKey] = Math.max(accumulatedMax[bandKey], bandRange.max)
    }
  }

  const invalidBands: EegBandKey[] = []
  const deviceWideMin = {} as Record<EegBandKey, number>
  const deviceWideMax = {} as Record<EegBandKey, number>

  for (const bandKey of EEG_BAND_KEYS) {
    const minValue = accumulatedMin[bandKey]
    const maxValue = accumulatedMax[bandKey]
    if (!Number.isFinite(minValue) || !Number.isFinite(maxValue) || maxValue <= minValue) {
      invalidBands.push(bandKey)
      deviceWideMin[bandKey] = 0
      deviceWideMax[bandKey] = 0
      continue
    }

    deviceWideMin[bandKey] = minValue
    deviceWideMax[bandKey] = maxValue
  }

  const isComplete = Object.values(completedModes).every(Boolean) && invalidBands.length === 0
  const latestModeTimestamp = Math.max(
    0,
    ...CALIBRATION_ACTIVITY_IDS
      .map((activityId) => modeStats[activityId]?.recordedAtMs ?? 0),
  )

  return {
    version: 1,
    recordedAtMs: recordedAtMsOverride ?? (latestModeTimestamp > 0 ? latestModeTimestamp : Date.now()),
    modeStats,
    completedModes,
    deviceWideMin,
    deviceWideMax,
    invalidBands,
    isComplete,
    capturePolicy: DEFAULT_EEG_CAPTURE_POLICY,
    deltaCaveat: true,
  }
}

const sanitizeEegCalibrationProfile = (value: unknown): EegCalibrationProfile | null => {
  if (!isRecord(value)) {
    return null
  }

  const modeSource = isRecord(value.modeStats) ? value.modeStats : value
  const modeStats: Partial<Record<CalibrationActivityId, EegCalibrationModeStats>> = {}

  for (const activityId of CALIBRATION_ACTIVITY_IDS) {
    const nextModeStats = sanitizeEegCalibrationModeStats(modeSource[activityId], activityId)
    if (nextModeStats !== null) {
      modeStats[activityId] = nextModeStats
    }
  }

  if (CALIBRATION_ACTIVITY_IDS.every((activityId) => modeStats[activityId] === undefined)) {
    return null
  }

  const recordedAtMs = sanitizeTimestampMs(value.recordedAtMs)
  return buildEegCalibrationProfile(modeStats, recordedAtMs ?? undefined)
}

const sanitizeDeviceCalibrationSummary = (value: unknown): DeviceCalibrationSummary => {
  if (!isRecord(value)) {
    return {}
  }

  const attention = sanitizeAttentionCalibrationSummary(value.attention)
  const alphaRelaxation = sanitizeAlphaRelaxationSummary(value.alphaRelaxation)
  const drowse = sanitizeDrowseCalibrationSummary(value.drowse)
  const eegProfile = sanitizeEegCalibrationProfile(value.eegProfile)

  if (attention === null && alphaRelaxation === null && drowse === null && eegProfile === null) {
    return {}
  }

  return {
    ...(attention === null ? {} : { attention }),
    ...(alphaRelaxation === null ? {} : { alphaRelaxation }),
    ...(drowse === null ? {} : { drowse }),
    ...(eegProfile === null ? {} : { eegProfile }),
  }
}

const hasCalibrationSummaryData = (value: DeviceCalibrationSummary): boolean => {
  return value.attention !== undefined
    || value.alphaRelaxation !== undefined
    || value.drowse !== undefined
    || value.eegProfile !== undefined
}

const sanitizeCalibrationSummaryMap = (value: unknown): Record<string, DeviceCalibrationSummary> => {
  if (!isRecord(value)) {
    return {}
  }

  const result: Record<string, DeviceCalibrationSummary> = {}
  for (const [mac, summary] of Object.entries(value)) {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      continue
    }

    const nextSummary = sanitizeDeviceCalibrationSummary(summary)
    if (
      nextSummary.attention !== undefined ||
      nextSummary.alphaRelaxation !== undefined ||
      nextSummary.drowse !== undefined ||
      nextSummary.eegProfile !== undefined
    ) {
      result[normalizedMac] = nextSummary
    }
  }

  return result
}

const sanitizeSelectedDevicesMap = (value: unknown): Record<string, string | null> => {
  if (!isRecord(value)) {
    return {}
  }

  const result: Record<string, string | null> = {}
  for (const capability of selectableCapabilities) {
    const selectedMac = value[capability]
    if (typeof selectedMac === 'string') {
      const normalizedSelectedMac = normalizeMacAddress(selectedMac)
      if (normalizedSelectedMac !== null) {
        result[capability] = normalizedSelectedMac
        continue
      }

      continue
    }

    if (selectedMac === null) {
      result[capability] = null
    }
  }

  return result
}

const sanitizeMacList = (value: unknown): string[] => {
  if (!Array.isArray(value)) {
    return []
  }

  const result: string[] = []
  for (const entry of value) {
    if (typeof entry !== 'string') {
      continue
    }

    const mac = normalizeMacAddress(entry)
    if (mac === null || result.includes(mac)) {
      continue
    }

    result.push(mac)
  }

  return result
}

const sanitizeCapabilities = (value: unknown): readonly string[] => {
  if (!Array.isArray(value)) {
    return []
  }

  const result: string[] = []
  for (const capability of value) {
    if (typeof capability !== 'string') {
      continue
    }

    const trimmedCapability = capability.trim()
    if (trimmedCapability === '' || result.includes(trimmedCapability)) {
      continue
    }

    result.push(trimmedCapability)
  }

  return result
}

const sanitizeDeviceInfo = (value: unknown): DeviceInfo | null => {
  if (!isRecord(value)) {
    return null
  }

  if (typeof value.mac !== 'string') {
    return null
  }

  const mac = normalizeMacAddress(value.mac)
  if (mac === null) {
    return null
  }

  const name = typeof value.name === 'string' ? value.name : ''
  const type = typeof value.type === 'string' ? value.type : 'unknown'
  const comPort = typeof value.comPort === 'string' && value.comPort.trim() !== ''
    ? value.comPort
    : undefined
  const index = typeof value.index === 'number' && Number.isFinite(value.index)
    ? value.index
    : -1
  const capabilities = sanitizeCapabilities(value.capabilities)

  return {
    index,
    mac,
    name,
    type,
    ...(comPort !== undefined ? { comPort } : {}),
    capabilities,
  }
}

const mergeCapabilities = (
  currentCapabilities: readonly string[],
  nextCapabilities: readonly string[],
): readonly string[] => {
  const result: string[] = []

  for (const capability of [...nextCapabilities, ...currentCapabilities]) {
    if (!result.includes(capability)) {
      result.push(capability)
    }
  }

  return result
}

const mergeDeviceInfo = (currentDevice: DeviceInfo, nextDevice: DeviceInfo): DeviceInfo => {
  const nextName = nextDevice.name.trim()
  const nextType = nextDevice.type.trim()
  const mergedDevice: DeviceInfo = {
    index: nextDevice.index,
    mac: currentDevice.mac,
    name: nextName !== '' ? nextDevice.name : currentDevice.name,
    type: nextType !== '' && nextType !== 'unknown' ? nextDevice.type : currentDevice.type,
    capabilities: mergeCapabilities(currentDevice.capabilities, nextDevice.capabilities),
  }

  const comPort = nextDevice.comPort ?? currentDevice.comPort
  if (comPort !== undefined && comPort !== '') {
    return { ...mergedDevice, comPort }
  }

  return mergedDevice
}

const upsertDeviceInfo = (devices: readonly DeviceInfo[], nextDevice: DeviceInfo): DeviceInfo[] => {
  const existingIndex = devices.findIndex((deviceInfo) => deviceInfo.mac === nextDevice.mac)
  if (existingIndex < 0) {
    return [...devices, nextDevice]
  }

  const nextDevices = [...devices]
  nextDevices[existingIndex] = mergeDeviceInfo(devices[existingIndex], nextDevice)
  return nextDevices
}

const sanitizeDeviceInfoList = (value: unknown): DeviceInfo[] => {
  if (!Array.isArray(value)) {
    return []
  }

  let result: DeviceInfo[] = []
  for (const entry of value) {
    const deviceInfo = sanitizeDeviceInfo(entry)
    if (deviceInfo !== null) {
      result = upsertDeviceInfo(result, deviceInfo)
    }
  }

  return result
}

const mergeDeviceInfoLists = (
  baseDevices: readonly DeviceInfo[],
  nextDevices: readonly DeviceInfo[],
): DeviceInfo[] => {
  let result = [...baseDevices]
  for (const nextDevice of nextDevices) {
    result = upsertDeviceInfo(result, nextDevice)
  }

  return result
}

const createPlaceholderDeviceInfo = (mac: string, capabilities: readonly string[]): DeviceInfo => ({
  index: -1,
  mac,
  name: '',
  type: 'unknown',
  capabilities: [...capabilities],
})

const collectSelectedCapabilitiesByMac = (value: Record<string, string | null>): Record<string, string[]> => {
  const result: Record<string, string[]> = {}

  for (const capability of selectableCapabilities) {
    const rawMac = value[capability]
    if (typeof rawMac !== 'string') {
      continue
    }

    const mac = normalizeMacAddress(rawMac)
    if (mac === null) {
      continue
    }

    if (result[mac] === undefined) {
      result[mac] = []
    }

    if (!result[mac].includes(capability)) {
      result[mac].push(capability)
    }
  }

  return result
}

const buildMigratedMarkedDevices = (
  selectedMap: Record<string, string | null>,
  foundDevices: readonly DeviceInfo[],
): DeviceInfo[] => {
  const selectedCapabilitiesByMac = collectSelectedCapabilitiesByMac(selectedMap)
  let result: DeviceInfo[] = []

  for (const [mac, capabilities] of Object.entries(selectedCapabilitiesByMac)) {
    const foundDevice = foundDevices.find((deviceInfo) => deviceInfo.mac === mac)
    result = upsertDeviceInfo(
      result,
      foundDevice ?? createPlaceholderDeviceInfo(mac, capabilities),
    )
  }

  return result
}

const syncMarkedDevicesWithFoundDevices = (
  markedDevices: readonly DeviceInfo[],
  foundDevices: readonly DeviceInfo[],
): DeviceInfo[] => {
  const foundDevicesByMac = new Map(foundDevices.map((deviceInfo) => [deviceInfo.mac, deviceInfo]))
  return markedDevices.map((markedDevice) => {
    const foundDevice = foundDevicesByMac.get(markedDevice.mac)
    return foundDevice === undefined ? markedDevice : mergeDeviceInfo(markedDevice, foundDevice)
  })
}

const syncInactiveDeviceMacsWithMarkedDevices = (
  inactiveDeviceMacs: readonly string[],
  markedDevices: readonly DeviceInfo[],
): string[] => {
  const markedMacs = new Set(markedDevices.map((deviceInfo) => deviceInfo.mac))
  return inactiveDeviceMacs.filter((mac) => markedMacs.has(mac))
}

const hasKnownCapabilityType = (deviceInfo: DeviceInfo): boolean => {
  return deviceInfo.capabilities.some((capability) => capabilityMeta[capability] !== undefined)
}

const sanitizeConnectTimeoutSec = (value: unknown): number => {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 1) {
    return DEFAULT_CONNECT_TIMEOUT_SEC
  }

  return Math.max(1, Math.trunc(parsed))
}

const sanitizeConnectTimeoutMap = (value: unknown): Record<string, number> => {
  if (!isRecord(value)) {
    return {}
  }

  const result: Record<string, number> = {}
  for (const [mac, timeoutValue] of Object.entries(value)) {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      continue
    }

    result[normalizedMac] = sanitizeConnectTimeoutSec(timeoutValue)
  }

  return result
}

const sanitizeEegStaleSec = (value: unknown): number => {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 1) {
    return DEFAULT_EEG_STALE_SEC
  }

  return Math.max(1, Math.trunc(parsed))
}

const sanitizeEegStaleSecMap = (value: unknown): Record<string, number> => {
  if (!isRecord(value)) {
    return {}
  }

  const result: Record<string, number> = {}
  for (const [mac, staleValue] of Object.entries(value)) {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      continue
    }

    result[normalizedMac] = sanitizeEegStaleSec(staleValue)
  }

  return result
}

function loadJson<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key)
    if (raw) return JSON.parse(raw) as T
  } catch { /* ignore */ }
  return fallback
}

export const useDeviceStore = defineStore('device', () => {
  const initialSelectedDevices = sanitizeSelectedDevicesMap(loadJson<unknown>(STORAGE_SELECTION, {}))
  const initialFoundDevices = sanitizeDeviceInfoList(loadJson<unknown>(STORAGE_FOUND_DEVICES, []))
  const hasStoredMarkedDevices = localStorage.getItem(STORAGE_MARKED_DEVICES) !== null
  const initialStoredMarkedDevices = hasStoredMarkedDevices
    ? sanitizeDeviceInfoList(loadJson<unknown>(STORAGE_MARKED_DEVICES, []))
    : []
  const migratedMarkedDevices = buildMigratedMarkedDevices(initialSelectedDevices, initialFoundDevices)
  const initialMarkedDevices = syncMarkedDevicesWithFoundDevices(
    hasStoredMarkedDevices
      ? mergeDeviceInfoLists(initialStoredMarkedDevices, migratedMarkedDevices)
      : migratedMarkedDevices,
    initialFoundDevices,
  )
  const initialInactiveDeviceMacs = syncInactiveDeviceMacsWithMarkedDevices(
    sanitizeMacList(loadJson<unknown>(STORAGE_INACTIVE_DEVICES, [])),
    initialMarkedDevices,
  )
  const initialCollapsedDeviceMacs = sanitizeMacList(loadJson<unknown>(STORAGE_COLLAPSED_DEVICES, []))

  const foundDevices = ref<DeviceInfo[]>(initialFoundDevices)
  const markedDevices = ref<DeviceInfo[]>(initialMarkedDevices)
  const inactiveDeviceMacs = ref<string[]>(initialInactiveDeviceMacs)
  const collapsedDeviceMacs = ref<string[]>(initialCollapsedDeviceMacs)
  const selectedDevices = ref<Record<string, string | null>>(initialSelectedDevices)
  const breathSettings = ref<Record<string, BreathSettings>>(
    sanitizeBreathSettingsMap(loadJson<unknown>(STORAGE_BREATH_SETTINGS, {})),
  )
  const connectTimeoutSecByDevice = ref<Record<string, number>>(
    sanitizeConnectTimeoutMap(loadJson<unknown>(STORAGE_CONNECT_TIMEOUTS, {})),
  )
  const eegStaleSecByDevice = ref<Record<string, number>>(
    sanitizeEegStaleSecMap(loadJson<unknown>(STORAGE_EEG_STALE_SEC, {})),
  )
  const calibrationSummariesByDevice = ref<Record<string, DeviceCalibrationSummary>>(
    sanitizeCalibrationSummaryMap(loadJson<unknown>(STORAGE_CALIBRATION_SUMMARIES, {})),
  )
  const browsing = ref(true)
  const pingStatesByMac = ref<Record<string, DevicePingStatus>>({})
  const scanProbeStatesByMac = ref<Record<string, DeviceScanProbeStatus>>({})

  watch(foundDevices, v => localStorage.setItem(STORAGE_FOUND_DEVICES, JSON.stringify(v)), { deep: true, immediate: true })
  watch(markedDevices, v => localStorage.setItem(STORAGE_MARKED_DEVICES, JSON.stringify(v)), { deep: true, immediate: true })
  watch(inactiveDeviceMacs, v => localStorage.setItem(STORAGE_INACTIVE_DEVICES, JSON.stringify(v)), { deep: true, immediate: true })
  watch(collapsedDeviceMacs, v => localStorage.setItem(STORAGE_COLLAPSED_DEVICES, JSON.stringify(v)), { deep: true, immediate: true })
  watch(selectedDevices, v => localStorage.setItem(STORAGE_SELECTION, JSON.stringify(v)), { deep: true, immediate: true })
  watch(breathSettings, v => localStorage.setItem(STORAGE_BREATH_SETTINGS, JSON.stringify(v)), { deep: true })
  watch(connectTimeoutSecByDevice, v => localStorage.setItem(STORAGE_CONNECT_TIMEOUTS, JSON.stringify(v)), { deep: true, immediate: true })
  watch(eegStaleSecByDevice, v => localStorage.setItem(STORAGE_EEG_STALE_SEC, JSON.stringify(v)), { deep: true, immediate: true })
  watch(calibrationSummariesByDevice, v => localStorage.setItem(STORAGE_CALIBRATION_SUMMARIES, JSON.stringify(v)), { deep: true, immediate: true })

  const deviceCount = computed(() => foundDevices.value.length)
  const hasFoundDevices = computed(() => foundDevices.value.length > 0)
  const hasMarkedDevices = computed(() => markedDevices.value.length > 0)
  const hasSelection = computed(() =>
    selectableCapabilities.some(capability => getSelectedMac(capability) != null),
  )
  const hasDevices = computed(() => foundDevices.value.length > 0 || markedDevices.value.length > 0)
  const foundDevicesByMac = computed(() => new Map(foundDevices.value.map((deviceInfo) => [deviceInfo.mac, deviceInfo])))
  const markedDevicesByMac = computed(() => new Map(markedDevices.value.map((deviceInfo) => [deviceInfo.mac, deviceInfo])))
  const inactiveDeviceMacSet = computed(() => new Set(inactiveDeviceMacs.value))
  const collapsedDeviceMacSet = computed(() => new Set(collapsedDeviceMacs.value))
  const devices = computed<readonly DeviceInfo[]>(() => foundDevices.value)
  const topListDevices = computed<readonly DeviceInfo[]>(() => markedDevices.value)
  const scanDevices = computed<readonly DeviceInfo[]>(() => {
    const topListMacs = new Set(markedDevices.value.map((deviceInfo) => deviceInfo.mac))
    const knownDevices: DeviceInfo[] = []
    const unknownDevices: DeviceInfo[] = []

    for (const deviceInfo of foundDevices.value) {
      if (topListMacs.has(deviceInfo.mac)) {
        continue
      }

      if (hasKnownCapabilityType(deviceInfo)) {
        knownDevices.push(deviceInfo)
        continue
      }

      unknownDevices.push(deviceInfo)
    }

    return [...knownDevices, ...unknownDevices]
  })
  const selectedDeviceInfos = computed<readonly DeviceInfo[]>(() => {
    const selectedCapabilitiesByMac = collectSelectedCapabilitiesByMac(selectedDevices.value)

    return Object.entries(selectedCapabilitiesByMac).map(([mac, capabilities]) => {
      const knownDevice = foundDevicesByMac.value.get(mac) ?? markedDevicesByMac.value.get(mac)
      return knownDevice ?? createPlaceholderDeviceInfo(mac, capabilities)
    })
  })
  const requiredConnectTargets = computed<Record<string, string>>(() => {
    const result: Record<string, string> = {}

    for (const capability of selectableCapabilities) {
      const mac = getSelectedMac(capability)
      if (mac === null) {
        continue
      }

      if (inactiveDeviceMacSet.value.has(mac)) {
        continue
      }

      const knownDevice = foundDevicesByMac.value.get(mac) ?? markedDevicesByMac.value.get(mac)
      if (knownDevice !== undefined && knownDevice.capabilities.includes(capability)) {
        result[capability] = mac
      }
    }

    return result
  })
  const requiredPingMacs = computed<readonly string[]>(() => {
    return Array.from(new Set(Object.values(requiredConnectTargets.value)))
  })
  const connectTargets = computed<Record<string, string>>(() => {
    const result: Record<string, string> = {}

    for (const [capability, mac] of Object.entries(requiredConnectTargets.value)) {
      if (foundDevicesByMac.value.has(mac) || isPingReady(mac)) {
        result[capability] = mac
      }
    }

    return result
  })
  const hasRequiredConnectTargets = computed(() => Object.keys(requiredConnectTargets.value).length > 0)
  const areAllRequiredConnectTargetsReady = computed(() => {
    const requiredCapabilities = Object.keys(requiredConnectTargets.value)
    return requiredCapabilities.length > 0 &&
      requiredCapabilities.every((capability) => connectTargets.value[capability] === requiredConnectTargets.value[capability])
  })

  function getSelectedMac(capability: string): string | null {
    if (!selectableCapabilitySet.has(capability)) {
      return null
    }

    return selectedDevices.value[capability] ?? null
  }

  function getConnectableMac(capability: string): string | null {
    if (!selectableCapabilitySet.has(capability)) {
      return null
    }

    return connectTargets.value[capability] ?? null
  }

  function isMarkedDevice(mac: string): boolean {
    return markedDevicesByMac.value.has(mac)
  }

  function isMarkedDeviceFound(mac: string): boolean {
    return foundDevicesByMac.value.has(mac)
  }

  function isDeviceInactive(mac: string): boolean {
    return inactiveDeviceMacSet.value.has(mac)
  }

  function isDeviceCardCollapsed(mac: string): boolean {
    return collapsedDeviceMacSet.value.has(mac)
  }

  function getPingState(mac: string): DevicePingState {
    return pingStatesByMac.value[mac]?.state ?? 'idle'
  }

  function isPingReady(mac: string): boolean {
    return getPingState(mac) === 'reachable'
  }

  function isPingInProgress(mac: string): boolean {
    return getPingState(mac) === 'pinging'
  }

  function getPingMessage(mac: string): string | null {
    return pingStatesByMac.value[mac]?.message ?? null
  }

  function getPingLastAttemptMs(mac: string): number | null {
    return pingStatesByMac.value[mac]?.lastAttemptMs ?? null
  }

  function getPingLastSuccessMs(mac: string): number | null {
    return pingStatesByMac.value[mac]?.lastSuccessMs ?? null
  }

  function isPingSuccessFresh(mac: string, maxAgeMs: number): boolean {
    const lastSuccessMs = getPingLastSuccessMs(mac)
    if (lastSuccessMs === null) {
      return false
    }

    return Date.now() - lastSuccessMs <= Math.max(0, Math.trunc(maxAgeMs))
  }

  function canSchedulePing(mac: string, minIntervalMs: number): boolean {
    const lastAttemptMs = getPingLastAttemptMs(mac)
    if (lastAttemptMs === null) {
      return true
    }

    return Date.now() - lastAttemptMs >= Math.max(0, Math.trunc(minIntervalMs))
  }

  function markPingPending(mac: string): void {
    if (!markedDevicesByMac.value.has(mac)) {
      return
    }

    const previous = pingStatesByMac.value[mac]
    pingStatesByMac.value = {
      ...pingStatesByMac.value,
      [mac]: {
        state: 'pinging',
        lastAttemptMs: Date.now(),
        lastSuccessMs: previous?.lastSuccessMs ?? null,
        ...(previous?.identifier !== undefined ? { identifier: previous.identifier } : {}),
        ...(previous?.message !== undefined ? { message: previous.message } : {}),
      },
    }
  }

  function clearPingState(mac: string): void {
    if (!(mac in pingStatesByMac.value)) {
      return
    }

    const nextStates = { ...pingStatesByMac.value }
    delete nextStates[mac]
    pingStatesByMac.value = nextStates
  }

  function handlePingResult(event: BodyMonitorPingResultEvent): void {
    if (!markedDevicesByMac.value.has(event.mac)) {
      return
    }

    const previous = pingStatesByMac.value[event.mac]
    pingStatesByMac.value = {
      ...pingStatesByMac.value,
      [event.mac]: {
        state: event.ok ? 'reachable' : 'unreachable',
        lastAttemptMs: previous?.lastAttemptMs ?? Date.now(),
        lastSuccessMs: event.ok ? Date.now() : previous?.lastSuccessMs ?? null,
        ...(event.identifier !== undefined ? { identifier: event.identifier } : previous?.identifier !== undefined ? { identifier: previous.identifier } : {}),
        ...(event.message !== undefined ? { message: event.message } : previous?.message !== undefined ? { message: previous.message } : {}),
      },
    }
  }

  function isCapabilityActive(capability: string, mac: string): boolean {
    return getSelectedMac(capability) === mac
  }

  function markDevice(deviceInfo: DeviceInfo) {
    markedDevices.value = upsertDeviceInfo(markedDevices.value, deviceInfo)
  }

  function selectCapabilitiesForDevice(mac: string, capabilities: readonly string[], overwriteExisting: boolean) {
    const nextSelectedDevices = { ...selectedDevices.value }
    let hasSelectedChanges = false

    for (const capability of capabilities) {
      if (!selectableCapabilitySet.has(capability)) {
        continue
      }

      if (!overwriteExisting && nextSelectedDevices[capability] !== null && nextSelectedDevices[capability] !== mac) {
        continue
      }

      if (nextSelectedDevices[capability] !== mac) {
        nextSelectedDevices[capability] = mac
        hasSelectedChanges = true
      }
    }

    if (hasSelectedChanges) {
      selectedDevices.value = nextSelectedDevices
    }
  }

  function rememberFoundDevice(deviceInfo: DeviceInfo) {
    if (!foundDevicesByMac.value.has(deviceInfo.mac)) {
      return
    }

    markDevice(deviceInfo)
    setDeviceInactive(deviceInfo.mac, false)
    selectCapabilitiesForDevice(deviceInfo.mac, deviceInfo.capabilities, true)
  }

  function setDeviceInactive(mac: string, inactive: boolean) {
    if (inactive) {
      if (!markedDevicesByMac.value.has(mac) || inactiveDeviceMacSet.value.has(mac)) {
        return
      }

      clearPingState(mac)
      inactiveDeviceMacs.value = [...inactiveDeviceMacs.value, mac]
      return
    }

    if (!inactiveDeviceMacSet.value.has(mac)) {
      return
    }

    inactiveDeviceMacs.value = inactiveDeviceMacs.value.filter((entry) => entry !== mac)
  }

  function setDeviceCardCollapsed(mac: string, collapsed: boolean) {
    if (collapsed) {
      if (collapsedDeviceMacSet.value.has(mac)) {
        return
      }

      collapsedDeviceMacs.value = [...collapsedDeviceMacs.value, mac]
      return
    }

    if (!collapsedDeviceMacSet.value.has(mac)) {
      return
    }

    collapsedDeviceMacs.value = collapsedDeviceMacs.value.filter((entry) => entry !== mac)
  }

  function activateFoundDevice(capability: string, deviceInfo: DeviceInfo) {
    if (!selectableCapabilitySet.has(capability) || !deviceInfo.capabilities.includes(capability)) {
      return
    }

    if (!foundDevicesByMac.value.has(deviceInfo.mac)) {
      return
    }

    markDevice(deviceInfo)
    setDeviceInactive(deviceInfo.mac, false)
    selectedDevices.value = { ...selectedDevices.value, [capability]: deviceInfo.mac }
  }

  function selectDevice(capability: string, mac: string) {
    browsing.value = false

    const foundDevice = foundDevicesByMac.value.get(mac)
    if (foundDevice !== undefined) {
      activateFoundDevice(capability, foundDevice)
      return
    }

    if (markedDevicesByMac.value.has(mac)) {
      setMarkedDeviceCapabilityActive(capability, mac, true)
    }
  }

  function setMarkedDeviceCapabilityActive(capability: string, mac: string, active: boolean) {
    if (!selectableCapabilitySet.has(capability)) {
      return
    }

    if (!active) {
      if (selectedDevices.value[capability] !== mac) {
        return
      }

      selectedDevices.value = { ...selectedDevices.value, [capability]: null }
      return
    }

    const knownDevice = foundDevicesByMac.value.get(mac) ?? markedDevicesByMac.value.get(mac)
    if (knownDevice === undefined || !knownDevice.capabilities.includes(capability)) {
      return
    }

    markDevice(knownDevice)
    setDeviceInactive(mac, false)
    selectedDevices.value = { ...selectedDevices.value, [capability]: mac }
  }

  function removeMarkedDevice(mac: string) {
    markedDevices.value = markedDevices.value.filter((deviceInfo) => deviceInfo.mac !== mac)
    inactiveDeviceMacs.value = inactiveDeviceMacs.value.filter((entry) => entry !== mac)
    clearPingState(mac)

    const nextSelectedDevices = { ...selectedDevices.value }
    let hasChanges = false
    for (const capability of selectableCapabilities) {
      if (nextSelectedDevices[capability] === mac) {
        nextSelectedDevices[capability] = null
        hasChanges = true
      }
    }

    if (hasChanges) {
      selectedDevices.value = nextSelectedDevices
    }
  }

  function getBreathSettings(mac: string): BreathSettings {
    return breathSettings.value[mac] ?? DEFAULT_BREATH_SETTINGS
  }

  function setBreathSettings(mac: string, nextSettings: BreathSettings) {
    breathSettings.value = {
      ...breathSettings.value,
      [mac]: sanitizeBreathSettings(nextSettings),
    }
  }

  function setBreathEnabled(mac: string, value: boolean) {
    const currentSettings = getBreathSettings(mac)
    setBreathSettings(mac, {
      ...currentSettings,
      enabled: value,
    })
  }

  function setBreathMinDelta(mac: string, value: number) {
    const currentSettings = getBreathSettings(mac)
    setBreathSettings(mac, {
      ...currentSettings,
      minDeltaMs: value,
    })
  }

  function setBreathMaxRr(mac: string, value: number) {
    const currentSettings = getBreathSettings(mac)
    setBreathSettings(mac, {
      ...currentSettings,
      maxRrMs: value,
    })
  }

  function getConnectTimeoutSec(mac: string): number {
    return connectTimeoutSecByDevice.value[mac] ?? DEFAULT_CONNECT_TIMEOUT_SEC
  }

  function setConnectTimeoutSec(mac: string, value: number) {
    connectTimeoutSecByDevice.value = {
      ...connectTimeoutSecByDevice.value,
      [mac]: sanitizeConnectTimeoutSec(value),
    }
  }

  function getConnectTimeoutMs(mac: string): number {
    return getConnectTimeoutSec(mac) * 1000
  }

  function getEegStaleSec(mac: string): number {
    return eegStaleSecByDevice.value[mac] ?? DEFAULT_EEG_STALE_SEC
  }

  function setEegStaleSec(mac: string, value: number) {
    eegStaleSecByDevice.value = {
      ...eegStaleSecByDevice.value,
      [mac]: sanitizeEegStaleSec(value),
    }
  }

  function getCalibrationSummary(mac: string): DeviceCalibrationSummary {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      return {}
    }

    return calibrationSummariesByDevice.value[normalizedMac] ?? {}
  }

  function getAttentionCalibrationSummary(mac: string): AttentionCalibrationSummary | null {
    return getCalibrationSummary(mac).attention ?? null
  }

  function getAlphaRelaxationSummary(mac: string): AlphaRelaxationSummary | null {
    return getCalibrationSummary(mac).alphaRelaxation ?? null
  }

  function getDrowseCalibrationSummary(mac: string): DrowseCalibrationSummary | null {
    return getCalibrationSummary(mac).drowse ?? null
  }

  function getEegCalibrationProfile(mac: string): EegCalibrationProfile | null {
    return getCalibrationSummary(mac).eegProfile ?? null
  }

  function getScanProbeStatus(mac: string): DeviceScanProbeStatus | null {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      return null
    }

    return scanProbeStatesByMac.value[normalizedMac] ?? null
  }

  function clearScanProbeStates() {
    scanProbeStatesByMac.value = {}
  }

  function replaceCalibrationSummary(mac: string, summary: DeviceCalibrationSummary) {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      return
    }

    if (!hasCalibrationSummaryData(summary)) {
      const nextSummaries = { ...calibrationSummariesByDevice.value }
      delete nextSummaries[normalizedMac]
      calibrationSummariesByDevice.value = nextSummaries
      return
    }

    calibrationSummariesByDevice.value = {
      ...calibrationSummariesByDevice.value,
      [normalizedMac]: summary,
    }
  }

  function setCalibrationSummary(mac: string, patch: Partial<DeviceCalibrationSummary>) {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      return
    }

    replaceCalibrationSummary(normalizedMac, {
      ...getCalibrationSummary(normalizedMac),
      ...patch,
    })
  }

  function clearCalibrationActivity(mac: string, activityId: CalibrationActivityId) {
    const normalizedMac = normalizeMacAddress(mac)
    if (normalizedMac === null) {
      return
    }

    const currentSummary = getCalibrationSummary(normalizedMac)
    const nextModeStats = { ...(currentSummary.eegProfile?.modeStats ?? {}) }
    delete nextModeStats[activityId]

    replaceCalibrationSummary(normalizedMac, {
      ...(activityId === 'attention' || currentSummary.attention === undefined
        ? {}
        : { attention: currentSummary.attention }),
      ...(activityId === 'alphaRelaxation' || currentSummary.alphaRelaxation === undefined
        ? {}
        : { alphaRelaxation: currentSummary.alphaRelaxation }),
      ...(activityId === 'drowse' || currentSummary.drowse === undefined
        ? {}
        : { drowse: currentSummary.drowse }),
      ...(Object.keys(nextModeStats).length === 0
        ? {}
        : { eegProfile: buildEegCalibrationProfile(nextModeStats) }),
    })
  }

  function setAttentionCalibrationSummary(mac: string, summary: AttentionCalibrationSummary) {
    const nextSummary = sanitizeAttentionCalibrationSummary(summary)
    if (nextSummary === null) {
      return
    }

    setCalibrationSummary(mac, { attention: nextSummary })
  }

  function setAlphaRelaxationSummary(mac: string, summary: AlphaRelaxationSummary) {
    const nextSummary = sanitizeAlphaRelaxationSummary(summary)
    if (nextSummary === null) {
      return
    }

    setCalibrationSummary(mac, { alphaRelaxation: nextSummary })
  }

  function setDrowseCalibrationSummary(mac: string, summary: DrowseCalibrationSummary) {
    const nextSummary = sanitizeDrowseCalibrationSummary(summary)
    if (nextSummary === null) {
      return
    }

    setCalibrationSummary(mac, { drowse: nextSummary })
  }

  function clearAttentionCalibrationSummary(mac: string) {
    clearCalibrationActivity(mac, 'attention')
  }

  function clearAlphaRelaxationSummary(mac: string) {
    clearCalibrationActivity(mac, 'alphaRelaxation')
  }

  function clearDrowseCalibrationSummary(mac: string) {
    clearCalibrationActivity(mac, 'drowse')
  }

  function setEegCalibrationModeStats(mac: string, modeStats: EegCalibrationModeStats) {
    const activityId = modeStats.activityId
    if (!CALIBRATION_ACTIVITY_IDS.includes(activityId)) {
      return
    }

    const nextModeStats = sanitizeEegCalibrationModeStats(modeStats, activityId)
    if (nextModeStats === null) {
      return
    }

    const currentModeStats = getEegCalibrationProfile(mac)?.modeStats ?? {}
    const mergedModeStats: Partial<Record<CalibrationActivityId, EegCalibrationModeStats>> = {
      ...currentModeStats,
      [activityId]: nextModeStats,
    }

    setCalibrationSummary(mac, {
      eegProfile: buildEegCalibrationProfile(mergedModeStats, nextModeStats.recordedAtMs),
    })
  }

  function isEcgSelected(mac: string): boolean {
    return getSelectedMac('ecg') === mac
  }

  function handleDevice(event: BodyMonitorDeviceEvent) {
    const previousMarkedDevice = markedDevicesByMac.value.get(event.device.mac)
    foundDevices.value = upsertDeviceInfo(foundDevices.value, event.device)

    if (previousMarkedDevice !== undefined) {
      markedDevices.value = syncMarkedDevicesWithFoundDevices(markedDevices.value, foundDevices.value)
      const newlyAvailableCapabilities = event.device.capabilities.filter(
        (capability) => !previousMarkedDevice.capabilities.includes(capability),
      )
      if (newlyAvailableCapabilities.length > 0) {
        selectCapabilitiesForDevice(event.device.mac, newlyAvailableCapabilities, false)
      }
    }
  }

  function handleDevices(event: BodyMonitorDevicesEvent) {
    const nextFoundDevices = sanitizeDeviceInfoList(event.devices)
    const nextMarkedDevices = syncMarkedDevicesWithFoundDevices(markedDevices.value, nextFoundDevices)
    foundDevices.value = nextFoundDevices
    markedDevices.value = nextMarkedDevices
    inactiveDeviceMacs.value = syncInactiveDeviceMacsWithMarkedDevices(
      inactiveDeviceMacs.value,
      nextMarkedDevices,
    )

    const nextMarkedMacs = new Set(nextMarkedDevices.map((deviceInfo) => deviceInfo.mac))
    const nextPingStates: Record<string, DevicePingStatus> = {}
    for (const [mac, pingStatus] of Object.entries(pingStatesByMac.value)) {
      if (nextMarkedMacs.has(mac)) {
        nextPingStates[mac] = pingStatus
      }
    }
    pingStatesByMac.value = nextPingStates

    const nextFoundMacs = new Set(nextFoundDevices.map((deviceInfo) => deviceInfo.mac))
    const nextScanProbeStates: Record<string, DeviceScanProbeStatus> = {}
    for (const [mac, probeStatus] of Object.entries(scanProbeStatesByMac.value)) {
      if (nextFoundMacs.has(mac)) {
        nextScanProbeStates[mac] = probeStatus
      }
    }
    scanProbeStatesByMac.value = nextScanProbeStates

  }

  function handleScanDeviceStatus(event: BodyMonitorScanDeviceStatusEvent) {
    scanProbeStatesByMac.value = {
      ...scanProbeStatesByMac.value,
      [event.mac]: {
        state: event.stage,
        totalCount: event.totalCount,
        completedCount: event.completedCount,
        ...(event.message !== undefined ? { message: event.message } : {}),
      },
    }
  }

  function clearFoundDevices() {
    foundDevices.value = []
    clearScanProbeStates()
    // inactiveDeviceMacs is deliberately NOT touched here.
    // It tracks only explicit user "не подключать" choices.
    // Scan availability is derived from foundDevices and should not mutate this persisted opt-out list.
  }

  function clearDevices() {
    browsing.value = true
    clearFoundDevices()
  }

  return {
    browsing,
    foundDevices,
    markedDevices,
    inactiveDeviceMacs,
    selectedDevices,
    breathSettings,
    calibrationSummariesByDevice,
    devices,
    topListDevices,
    scanDevices,
    selectedDeviceInfos,
    deviceCount,
    hasDevices,
    hasFoundDevices,
    hasMarkedDevices,
    hasSelection,
    requiredPingMacs,
    hasRequiredConnectTargets,
    areAllRequiredConnectTargetsReady,
    connectTargets,
    getSelectedMac,
    getConnectableMac,
    isMarkedDevice,
    isMarkedDeviceFound,
    isDeviceInactive,
    isDeviceCardCollapsed,
    getPingState,
    isPingReady,
    isPingInProgress,
    getPingMessage,
    getPingLastAttemptMs,
    getPingLastSuccessMs,
    isPingSuccessFresh,
    canSchedulePing,
    getScanProbeStatus,
    isCapabilityActive,
    rememberFoundDevice,
    activateFoundDevice,
    selectDevice,
    setMarkedDeviceCapabilityActive,
    setDeviceInactive,
    setDeviceCardCollapsed,
    markPingPending,
    clearPingState,
    removeMarkedDevice,
    getBreathSettings,
    getConnectTimeoutSec,
    getEegStaleSec,
    getCalibrationSummary,
    getAttentionCalibrationSummary,
    getAlphaRelaxationSummary,
    getDrowseCalibrationSummary,
    getEegCalibrationProfile,
    setBreathEnabled,
    setBreathMinDelta,
    setBreathMaxRr,
    setConnectTimeoutSec,
    setEegStaleSec,
    setAttentionCalibrationSummary,
    setAlphaRelaxationSummary,
    setDrowseCalibrationSummary,
    clearAttentionCalibrationSummary,
    clearAlphaRelaxationSummary,
    clearDrowseCalibrationSummary,
    setEegCalibrationModeStats,
    getConnectTimeoutMs,
    isEcgSelected,
    handleDevice,
    handleDevices,
    handlePingResult,
    handleScanDeviceStatus,
    clearDevices,
    clearFoundDevices,
  }
})

