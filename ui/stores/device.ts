import { defineStore } from 'pinia'
import { computed, ref, watch } from 'vue'
import type {
  DeviceInfo,
  BodyMonitorDeviceEvent,
  BodyMonitorDevicesEvent,
} from '@protocol'

export interface BreathSettings {
  readonly enabled: boolean
  readonly minDeltaMs: number
  readonly maxRrMs: number
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

const STORAGE_FOUND_DEVICES = 'mw_devices'
const STORAGE_MARKED_DEVICES = 'mw_markedDevices'
const STORAGE_SELECTION = 'mw_selectedDevices'
const STORAGE_BREATH_SETTINGS = 'mw_breathSettings'
const STORAGE_CONNECT_TIMEOUTS = 'mw_connectTimeoutSecByDevice'
const STORAGE_EEG_STALE_SEC = 'mw_eegStaleSecByDevice'

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
    result[mac] = sanitizeBreathSettings(settings)
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
    if (typeof selectedMac === 'string' && selectedMac.trim() !== '') {
      result[capability] = selectedMac
      continue
    }

    if (selectedMac === null) {
      result[capability] = null
    }
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

  const mac = typeof value.mac === 'string' ? value.mac.trim() : ''
  if (mac === '') {
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
    const mac = value[capability]
    if (typeof mac !== 'string' || mac.trim() === '') {
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

const deactivateSelectionsMissingFromFoundDevices = (
  selectedMap: Record<string, string | null>,
  foundDevices: readonly DeviceInfo[],
): Record<string, string | null> => {
  const foundDevicesByMac = new Map(foundDevices.map((deviceInfo) => [deviceInfo.mac, deviceInfo]))
  let hasChanges = false
  const nextSelectedMap = { ...selectedMap }

  for (const capability of selectableCapabilities) {
    const mac = nextSelectedMap[capability]
    if (typeof mac !== 'string' || mac.trim() === '') {
      continue
    }

    const foundDevice = foundDevicesByMac.get(mac)
    if (foundDevice !== undefined && foundDevice.capabilities.includes(capability)) {
      continue
    }

    nextSelectedMap[capability] = null
    hasChanges = true
  }

  return hasChanges ? nextSelectedMap : selectedMap
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
    result[mac] = sanitizeConnectTimeoutSec(timeoutValue)
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
    result[mac] = sanitizeEegStaleSec(staleValue)
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

  const foundDevices = ref<DeviceInfo[]>(initialFoundDevices)
  const markedDevices = ref<DeviceInfo[]>(
    syncMarkedDevicesWithFoundDevices(
      hasStoredMarkedDevices
        ? mergeDeviceInfoLists(initialStoredMarkedDevices, migratedMarkedDevices)
        : migratedMarkedDevices,
      initialFoundDevices,
    ),
  )
  const selectedDevices = ref<Record<string, string | null>>(
    deactivateSelectionsMissingFromFoundDevices(initialSelectedDevices, initialFoundDevices),
  )
  const breathSettings = ref<Record<string, BreathSettings>>(
    sanitizeBreathSettingsMap(loadJson<unknown>(STORAGE_BREATH_SETTINGS, {})),
  )
  const connectTimeoutSecByDevice = ref<Record<string, number>>(
    sanitizeConnectTimeoutMap(loadJson<unknown>(STORAGE_CONNECT_TIMEOUTS, {})),
  )
  const eegStaleSecByDevice = ref<Record<string, number>>(
    sanitizeEegStaleSecMap(loadJson<unknown>(STORAGE_EEG_STALE_SEC, {})),
  )
  const browsing = ref(true)

  watch(foundDevices, v => localStorage.setItem(STORAGE_FOUND_DEVICES, JSON.stringify(v)), { deep: true, immediate: true })
  watch(markedDevices, v => localStorage.setItem(STORAGE_MARKED_DEVICES, JSON.stringify(v)), { deep: true, immediate: true })
  watch(selectedDevices, v => localStorage.setItem(STORAGE_SELECTION, JSON.stringify(v)), { deep: true, immediate: true })
  watch(breathSettings, v => localStorage.setItem(STORAGE_BREATH_SETTINGS, JSON.stringify(v)), { deep: true })
  watch(connectTimeoutSecByDevice, v => localStorage.setItem(STORAGE_CONNECT_TIMEOUTS, JSON.stringify(v)), { deep: true, immediate: true })
  watch(eegStaleSecByDevice, v => localStorage.setItem(STORAGE_EEG_STALE_SEC, JSON.stringify(v)), { deep: true, immediate: true })

  const deviceCount = computed(() => foundDevices.value.length)
  const hasFoundDevices = computed(() => foundDevices.value.length > 0)
  const hasMarkedDevices = computed(() => markedDevices.value.length > 0)
  const hasSelection = computed(() =>
    selectableCapabilities.some(capability => getSelectedMac(capability) != null),
  )
  const hasDevices = computed(() => foundDevices.value.length > 0)
  const foundDevicesByMac = computed(() => new Map(foundDevices.value.map((deviceInfo) => [deviceInfo.mac, deviceInfo])))
  const markedDevicesByMac = computed(() => new Map(markedDevices.value.map((deviceInfo) => [deviceInfo.mac, deviceInfo])))
  const devices = computed<readonly DeviceInfo[]>(() => foundDevices.value)
  const selectedDeviceInfos = computed<readonly DeviceInfo[]>(() => {
    const selectedCapabilitiesByMac = collectSelectedCapabilitiesByMac(selectedDevices.value)

    return Object.entries(selectedCapabilitiesByMac).map(([mac, capabilities]) => {
      const knownDevice = foundDevicesByMac.value.get(mac) ?? markedDevicesByMac.value.get(mac)
      return knownDevice ?? createPlaceholderDeviceInfo(mac, capabilities)
    })
  })
  const connectTargets = computed<Record<string, string>>(() => {
    const result: Record<string, string> = {}

    for (const capability of selectableCapabilities) {
      const mac = getSelectedMac(capability)
      if (mac === null) {
        continue
      }

      const foundDevice = foundDevicesByMac.value.get(mac)
      if (foundDevice !== undefined && foundDevice.capabilities.includes(capability)) {
        result[capability] = mac
      }
    }

    return result
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

  function isCapabilityActive(capability: string, mac: string): boolean {
    return getSelectedMac(capability) === mac
  }

  function markDevice(deviceInfo: DeviceInfo) {
    markedDevices.value = upsertDeviceInfo(markedDevices.value, deviceInfo)
  }

  function activateFoundDevice(capability: string, deviceInfo: DeviceInfo) {
    if (!selectableCapabilitySet.has(capability) || !deviceInfo.capabilities.includes(capability)) {
      return
    }

    if (!foundDevicesByMac.value.has(deviceInfo.mac)) {
      return
    }

    markDevice(deviceInfo)
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

    const foundDevice = foundDevicesByMac.value.get(mac)
    if (foundDevice === undefined || !foundDevice.capabilities.includes(capability)) {
      return
    }

    markDevice(foundDevice)
    selectedDevices.value = { ...selectedDevices.value, [capability]: mac }
  }

  function removeMarkedDevice(mac: string) {
    markedDevices.value = markedDevices.value.filter((deviceInfo) => deviceInfo.mac !== mac)

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

  function isEcgSelected(mac: string): boolean {
    return getSelectedMac('ecg') === mac
  }

  function handleDevice(event: BodyMonitorDeviceEvent) {
    foundDevices.value = upsertDeviceInfo(foundDevices.value, event.device)

    if (markedDevicesByMac.value.has(event.device.mac)) {
      markedDevices.value = syncMarkedDevicesWithFoundDevices(markedDevices.value, foundDevices.value)
    }
  }

  function handleDevices(event: BodyMonitorDevicesEvent) {
    const nextFoundDevices = sanitizeDeviceInfoList(event.devices)
    foundDevices.value = nextFoundDevices
    markedDevices.value = syncMarkedDevicesWithFoundDevices(markedDevices.value, nextFoundDevices)
    selectedDevices.value = deactivateSelectionsMissingFromFoundDevices(selectedDevices.value, nextFoundDevices)
  }

  function clearFoundDevices() {
    foundDevices.value = []
  }

  function clearDevices() {
    browsing.value = true
    clearFoundDevices()
  }

  return {
    browsing,
    foundDevices,
    markedDevices,
    selectedDevices,
    breathSettings,
    devices,
    selectedDeviceInfos,
    deviceCount,
    hasDevices,
    hasFoundDevices,
    hasMarkedDevices,
    hasSelection,
    connectTargets,
    getSelectedMac,
    getConnectableMac,
    isMarkedDevice,
    isMarkedDeviceFound,
    isCapabilityActive,
    activateFoundDevice,
    selectDevice,
    setMarkedDeviceCapabilityActive,
    removeMarkedDevice,
    getBreathSettings,
    getConnectTimeoutSec,
    getEegStaleSec,
    setBreathEnabled,
    setBreathMinDelta,
    setBreathMaxRr,
    setConnectTimeoutSec,
    setEegStaleSec,
    getConnectTimeoutMs,
    isEcgSelected,
    handleDevice,
    handleDevices,
    clearDevices,
    clearFoundDevices,
  }
})

