import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type {
  BodyMonitorState,
  BodyMonitorStatusEvent,
  BodyMonitorStartedEvent,
  BodyMonitorScanCommandEvent,
  BodyMonitorOutputEvent,
  BodyMonitorExitEvent,
  BodyMonitorErrorEvent,
  BodyMonitorStdioAckEvent
} from '@protocol'
import { useDeviceStore } from 'stores/device'
import { appendParsedOutputToLogChart, createEmptyChartSnapshot } from 'src/utils/log-chart'

const RAW_LINES_MAX = 1000

export interface ScanStatus {
  readonly key: 'found' | 'error' | 'complete' | 'other' | 'progress'
  readonly identifier?: string
  readonly mac?: string
  readonly message?: string
  readonly text?: string
  readonly deviceCount?: number
  readonly elapsedSec?: number
  readonly translationKey?: string
  readonly translationParams?: Record<string, string | number>
}

export type DeviceConnectionState = 'online' | 'offline'

interface RuntimeDeviceStateEvent {
  readonly mac: string
  readonly state: DeviceConnectionState
  readonly source: 'ecg' | 'eeg'
}

const BLE_SCAN_COUNT_PATTERN = /^Found (\d+) BLE device\(s\)\.$/
const BLE_SCAN_DEVICE_PATTERN = /^\s*\[\d+\]\s+(.*)\s+\[([^\]]+)\]\s*$/
const BLE_PAIRING_ATTEMPT_PATTERN = /^\s*Pairing attempt for (.*) \[([^\]]+)\]\.\.\.$/
const BLE_FILTER_ADDRESS_PATTERN = /^ECG address filter active: exact match "(.*)"\.$/
const BLE_FILTER_NAME_PATTERN = /^ECG name filter active: contains "(.*)" \(case-insensitive\)\.$/
const BLE_HEART_RATE_FOUND_PATTERN = /^Found Heart Rate device: (.*) \[([^\]]+)\]$/
const BLE_HEART_RATE_CACHED_PATTERN = /^Using cached Heart Rate device: (.*) \[([^\]]+)\]$/
const EEG_CONNECT_FALLBACK_PATTERN = /^TG_Connect failed for (.+) \((-?\d+)\)\. Trying (.+)\.\.\.$/
const EEG_CONNECT_FAILED_PATTERN = /^TG_Connect failed for (.+) \((-?\d+)\)\. Retry in 2 seconds\.\.\.$/
const EEG_CONNECTED_PATTERN = /^Connected to (.+)$/
const EEG_SDK_VERSION_PATTERN = /^Stream SDK for PC version: (\d+)$/

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}

function parseScanCancellationStatus(value: string): ScanStatus | null {
  if (
    value === 'Cancelled' ||
    value === 'Canceled' ||
    value === 'BLE scan cancelled.' ||
    value === 'list_devices_cancelled'
  ) {
    return createTranslatedStatus('other', 'settings.scanCancelled', {}, { message: value, text: value })
  }

  return null
}

function createTranslatedStatus(
  key: ScanStatus['key'],
  translationKey: string,
  translationParams: Record<string, string | number> = {},
  extra: Partial<ScanStatus> = {},
): ScanStatus {
  return {
    key,
    translationKey,
    translationParams,
    ...extra,
  }
}

function parseBleScanStatus(message: string): ScanStatus | null {
  const cancellationStatus = parseScanCancellationStatus(message)
  if (cancellationStatus !== null) {
    return cancellationStatus
  }

  if (message === 'Connecting to cached Heart Rate device...') {
    return createTranslatedStatus('other', 'settings.bleConnectCached', {}, { message, text: message })
  }

  if (message === 'Cached Heart Rate device reconnect failed. Falling back to fresh BLE scan.') {
    return createTranslatedStatus('other', 'settings.bleConnectCachedFallback', {}, { message, text: message })
  }

  if (message === 'ERROR: Failed to connect to cached Heart Rate device.') {
    return createTranslatedStatus('error', 'settings.bleConnectCachedFailed', {}, { message, text: message })
  }

  const pairingAttemptMatch = message.match(BLE_PAIRING_ATTEMPT_PATTERN)
  if (pairingAttemptMatch !== null) {
    const [, name, mac] = pairingAttemptMatch
    return createTranslatedStatus(
      'other',
      'settings.blePairingAttempt',
      { name, mac },
      { identifier: name, mac, message, text: message },
    )
  }

  const addressMatch = message.match(BLE_FILTER_ADDRESS_PATTERN)
  if (addressMatch !== null) {
    return createTranslatedStatus('other', 'settings.bleFilterAddress', { value: addressMatch[1] }, { message, text: message })
  }

  const nameMatch = message.match(BLE_FILTER_NAME_PATTERN)
  if (nameMatch !== null) {
    return createTranslatedStatus('other', 'settings.bleFilterName', { value: nameMatch[1] }, { message, text: message })
  }

  if (message === 'ERROR: BLE scan failed.') {
    return createTranslatedStatus('error', 'settings.bleScanFailed', {}, { message, text: message })
  }

  if (message === 'ERROR: No Heart Rate device found.') {
    return createTranslatedStatus('error', 'settings.bleNoHeartRateDevice', {}, { message, text: message })
  }

  const countMatch = message.match(BLE_SCAN_COUNT_PATTERN)
  if (countMatch !== null) {
    return createTranslatedStatus('other', 'settings.bleScanResultsCount', { count: Number(countMatch[1]) }, { message, text: message })
  }

  const deviceMatch = message.match(BLE_SCAN_DEVICE_PATTERN)
  if (deviceMatch !== null) {
    const [, name, mac] = deviceMatch
    return createTranslatedStatus(
      'found',
      'settings.statusFound',
      { name, mac },
      { identifier: name, mac, message, text: message },
    )
  }

  const cachedMatch = message.match(BLE_HEART_RATE_CACHED_PATTERN)
  if (cachedMatch !== null) {
    const [, name, mac] = cachedMatch
    return createTranslatedStatus(
      'other',
      'settings.bleHeartRateDeviceCached',
      { name, mac },
      { identifier: name, mac, message, text: message },
    )
  }

  const foundMatch = message.match(BLE_HEART_RATE_FOUND_PATTERN)
  if (foundMatch !== null) {
    const [, name, mac] = foundMatch
    return createTranslatedStatus(
      'other',
      'settings.bleHeartRateDeviceFound',
      { name, mac },
      { identifier: name, mac, message, text: message },
    )
  }

  if (message === 'Subscribed to Heart Rate notifications.') {
    return createTranslatedStatus('other', 'settings.bleSubscribeReady', {}, { message, text: message })
  }

  if (message === 'ERROR: Failed to subscribe to Heart Rate notifications.') {
    return createTranslatedStatus('error', 'settings.bleSubscribeFailed', {}, { message, text: message })
  }

  if (message === 'ERROR: Heart Rate Measurement characteristic not found.') {
    return createTranslatedStatus('error', 'settings.bleCharacteristicMissing', {}, { message, text: message })
  }

  return null
}

function parseEegConnectStatus(
  stage: string,
  message: string,
  port?: string,
  errorCode?: number,
): ScanStatus | null {
  switch (stage) {
    case 'wait':
      return createTranslatedStatus('other', 'settings.eegWait', {}, { message, text: message })

    case 'connect_attempt':
      if (message === 'Trying TG_Connect (alternate)') {
        return createTranslatedStatus('other', 'settings.eegConnectAttemptAlternate', { port: port ?? '' }, { message, text: message })
      }

      if (message === 'Trying TG_Connect') {
        return createTranslatedStatus('other', 'settings.eegConnectAttempt', { port: port ?? '' }, { message, text: message })
      }

      break

    case 'connect_fallback':
      return createTranslatedStatus(
        'other',
        'settings.eegConnectFallback',
        { port: port ?? '', errorCode: errorCode ?? 0 },
        { message, text: message },
      )

    case 'connect_failed':
      return createTranslatedStatus(
        'error',
        'settings.eegConnectFailed',
        { port: port ?? '', errorCode: errorCode ?? 0 },
        { message, text: message },
      )

    case 'connected':
      return createTranslatedStatus('other', 'settings.eegConnected', { port: port ?? '' }, { message, text: message })

    case 'disconnected':
      return createTranslatedStatus('error', 'settings.eegDisconnected', {}, { message, text: message })

    case 'reconnected':
      return createTranslatedStatus('other', 'settings.eegReconnected', {}, { message, text: message })
  }

  return null
}

function parseEegInitStatus(message: string, version?: number): ScanStatus | null {
  if (message === 'Stream SDK for PC version') {
    return createTranslatedStatus('other', 'settings.eegSdkVersion', { version: version ?? 0 }, { message, text: message })
  }

  return null
}

function parsePlainStatus(line: string): ScanStatus | null {
  const cancellationStatus = parseScanCancellationStatus(line)
  if (cancellationStatus !== null) {
    return cancellationStatus
  }

  const bleStatus = parseBleScanStatus(line)
  if (bleStatus !== null) {
    return bleStatus
  }

  if (line === 'Waiting for headset connection... Press Ctrl+C to abort.') {
    return createTranslatedStatus('other', 'settings.eegWait', {}, { message: line, text: line })
  }

  if (line === 'Hint: TG_Connect(-2) means the COM port could not be opened.') {
    return createTranslatedStatus('error', 'settings.eegHintPortOpen', {}, { message: line, text: line })
  }

  if (line === 'Check that the port name is correct, the port is not busy, and the headset is paired and connected.') {
    return createTranslatedStatus('error', 'settings.eegHintCheckPort', {}, { message: line, text: line })
  }

  if (line === 'This SDK supports MindWave Mobile and MindWave Mobile 1.5.') {
    return createTranslatedStatus('error', 'settings.eegHintSupported', {}, { message: line, text: line })
  }

  if (line === 'Hint: invalid baud rate passed to TG_Connect. Expected TG_BAUD_57600.') {
    return createTranslatedStatus('error', 'settings.eegHintBaud', {}, { message: line, text: line })
  }

  if (line === 'Hint: invalid data format passed to TG_Connect. Expected TG_STREAM_PACKETS.') {
    return createTranslatedStatus('error', 'settings.eegHintStream', {}, { message: line, text: line })
  }

  const connectFallbackMatch = line.match(EEG_CONNECT_FALLBACK_PATTERN)
  if (connectFallbackMatch !== null) {
    const [, port, errorCode, alternatePort] = connectFallbackMatch
    return createTranslatedStatus(
      'other',
      'settings.eegConnectFallbackConsole',
      { port, errorCode: Number(errorCode), alternatePort },
      { message: line, text: line },
    )
  }

  const connectFailedMatch = line.match(EEG_CONNECT_FAILED_PATTERN)
  if (connectFailedMatch !== null) {
    const [, port, errorCode] = connectFailedMatch
    return createTranslatedStatus(
      'error',
      'settings.eegConnectFailed',
      { port, errorCode: Number(errorCode) },
      { message: line, text: line },
    )
  }

  const connectedMatch = line.match(EEG_CONNECTED_PATTERN)
  if (connectedMatch !== null) {
    return createTranslatedStatus(
      'other',
      'settings.eegConnected',
      { port: connectedMatch[1] },
      { message: line, text: line },
    )
  }

  const sdkVersionMatch = line.match(EEG_SDK_VERSION_PATTERN)
  if (sdkVersionMatch !== null) {
    return createTranslatedStatus(
      'other',
      'settings.eegSdkVersion',
      { version: Number(sdkVersionMatch[1]) },
      { message: line, text: line },
    )
  }

  return null
}

function parseScanLine(line: string): ScanStatus {
  try {
    const obj = JSON.parse(line) as Record<string, unknown>
    const event = typeof obj['event'] === 'string' ? obj['event'] : ''
    const level = typeof obj['level'] === 'string' ? obj['level'] : ''
    const message = typeof obj['message'] === 'string' ? obj['message'] : ''

    const eventCancellationStatus = parseScanCancellationStatus(event)
    if (eventCancellationStatus !== null) {
      return eventCancellationStatus
    }

    if (event === 'ble_scan') {
      const stage = typeof obj['stage'] === 'string' ? obj['stage'] : ''

      if (level === 'error') {
        const translatedStatus = parseBleScanStatus(message)
        if (translatedStatus !== null) {
          return translatedStatus
        }

        return { key: 'error', message }
      }

      if (stage === 'scan_start') {
        return { key: 'progress', message, elapsedSec: 0 }
      }

      const translatedStatus = parseBleScanStatus(message)
      if (translatedStatus !== null) {
        return translatedStatus
      }

      return { key: 'other', text: message || line.slice(0, 80) }
    }

    if (event === 'eeg_connect') {
      const stage = typeof obj['stage'] === 'string' ? obj['stage'] : ''
      const port = typeof obj['port'] === 'string' ? obj['port'] : undefined
      const errorCode = typeof obj['error_code'] === 'number' ? obj['error_code'] : undefined
      const translatedStatus = parseEegConnectStatus(stage, message, port, errorCode)

      if (translatedStatus !== null) {
        return translatedStatus
      }

      return { key: level === 'error' ? 'error' : 'other', message, text: message }
    }

    if (event === 'eeg_init') {
      const version = typeof obj['version'] === 'number' ? obj['version'] : undefined
      const translatedStatus = parseEegInitStatus(message, version)

      if (translatedStatus !== null) {
        return translatedStatus
      }

      return { key: 'other', message, text: message || event }
    }

    if (event === 'ble_device') {
      const identifier = typeof obj['identifier'] === 'string' ? obj['identifier'] : ''
      const mac = typeof obj['mac'] === 'string' ? obj['mac'] : ''
      if (level === 'info') {
        return { key: 'found', identifier, mac, message }
      }
      if (level === 'error') {
        return { key: 'error', identifier, message }
      }
    }
    if (message !== '') {
      return { key: level === 'error' ? 'error' : 'other', message, text: message }
    }
    if (event !== '') {
      return { key: 'other', text: event }
    }
  } catch {
    // not JSON
  }

  const translatedStatus = parsePlainStatus(line)
  if (translatedStatus !== null) {
    return translatedStatus
  }

  return { key: 'other', text: line.slice(0, 80) }
}

function parseRuntimeDeviceState(value: unknown, selectedEegMac: string | null): RuntimeDeviceStateEvent | null {
  if (!isRecord(value)) {
    return null
  }

  const event = typeof value['event'] === 'string' ? value['event'] : ''
  const mac = typeof value['mac'] === 'string' ? value['mac'] : ''
  const state = typeof value['state'] === 'string' ? value['state'] : ''
  const source = typeof value['source'] === 'string' ? value['source'] : ''

  if (event !== 'ble_connection' || source !== 'ecg' || mac === '') {
    if (event !== 'eeg_connect' || source !== 'eeg' || selectedEegMac === null) {
      return null
    }

    const stage = typeof value['stage'] === 'string' ? value['stage'] : ''
    if (stage === 'disconnected') {
      return {
        mac: selectedEegMac,
        state: 'offline',
        source: 'eeg',
      }
    }

    if (stage === 'connected' || stage === 'reconnected') {
      return {
        mac: selectedEegMac,
        state: 'online',
        source: 'eeg',
      }
    }

    return null
  }

  if (state !== 'offline' && state !== 'online') {
    return null
  }

  return {
    mac,
    state,
    source: 'ecg',
  }
}

function isConnectReadyLine(line: string): boolean {
  try {
    const obj = JSON.parse(line) as Record<string, unknown>
    const event = typeof obj['event'] === 'string' ? obj['event'] : ''

    if (event === 'hr_notification' || event === 'breath_phase') {
      return true
    }

    if (event === 'ble_scan') {
      const stage = typeof obj['stage'] === 'string' ? obj['stage'] : ''
      return stage === 'subscribe'
    }
  } catch {
    // not JSON
  }

  return false
}

function parseConnectedCapability(line: string, parsedJson: unknown): string | null {
  if (isRecord(parsedJson)) {
    const event = typeof parsedJson['event'] === 'string' ? parsedJson['event'] : ''

    if (event === 'hr_notification' || event === 'breath_phase') {
      return 'ecg'
    }

    if (event === 'ble_scan') {
      const stage = typeof parsedJson['stage'] === 'string' ? parsedJson['stage'] : ''
      if (stage === 'subscribe') {
        return 'ecg'
      }
    }

    if (event === 'eeg_connect') {
      const stage = typeof parsedJson['stage'] === 'string' ? parsedJson['stage'] : ''
      if (stage === 'connected' || stage === 'reconnected') {
        return 'eeg'
      }
    }
  }

  return EEG_CONNECTED_PATTERN.test(line) ? 'eeg' : null
}

export const useSessionStore = defineStore('session', () => {
  const exeState = ref<BodyMonitorState>('idle')
  const bodyMonitorState = ref<BodyMonitorState>('idle')
  const activeRunId = ref<string | null>(null)
  const rawLines = ref<string[]>([])
  const chartData = ref(createEmptyChartSnapshot())
  const lastError = ref<string | null>(null)
  const scanStatus = ref<ScanStatus | null>(null)
  const scanCommandLine = ref('')
  const activeCommandLine = ref('')
  const isScanning = ref(false)
  const isConnecting = ref(false)
  const connectReadyToken = ref(0)
  const connectStopRequestToken = ref(0)
  const scanDone = ref(false)
  const scanStartedAtMs = ref<number | null>(null)
  const deviceConnectionStates = ref<Record<string, DeviceConnectionState>>({})
  const connectTargets = ref<Record<string, string>>({})
  const connectedTargets = ref<Record<string, boolean>>({})
  const failedTargets = ref<Record<string, boolean>>({})
  let scanElapsedTimer: ReturnType<typeof setInterval> | null = null
  const connectTimeoutHandles = new Map<string, ReturnType<typeof setTimeout>>()
  let connectStopRequested = false

  const canStart = computed(() =>
    exeState.value === 'running' &&
    bodyMonitorState.value === 'idle' &&
    !isScanning.value &&
    !isConnecting.value,
  )
  const canScan = computed(() =>
    exeState.value === 'running' &&
    !isScanning.value &&
    !isConnecting.value,
  )
  const canStop = computed(() => bodyMonitorState.value === 'running' || bodyMonitorState.value === 'starting')

  const stateColor = computed(() => {
    switch (bodyMonitorState.value) {
      case 'running': return 'positive'
      case 'starting': return 'warning'
      case 'stopping': return 'warning'
      default: return 'grey'
    }
  })

  function getScanElapsedSec(): number {
    if (scanStartedAtMs.value === null) {
      return 0
    }

    return Math.max(0, Math.floor((Date.now() - scanStartedAtMs.value) / 1000))
  }

  function refreshScanElapsedSec() {
    if (!isScanning.value || scanStartedAtMs.value === null) {
      return
    }

    const elapsedSec = getScanElapsedSec()

    if (scanStatus.value === null) {
      scanStatus.value = { key: 'progress', elapsedSec }
      return
    }

    scanStatus.value = {
      ...scanStatus.value,
      elapsedSec,
    }
  }

  function stopElapsedTimer() {
    if (scanElapsedTimer !== null) {
      clearInterval(scanElapsedTimer)
      scanElapsedTimer = null
    }
  }

  function startElapsedTimer() {
    stopElapsedTimer()
    scanElapsedTimer = setInterval(() => {
      refreshScanElapsedSec()
    }, 1000)
  }

  function setDeviceConnectionState(mac: string, state: DeviceConnectionState) {
    deviceConnectionStates.value = {
      ...deviceConnectionStates.value,
      [mac]: state,
    }
  }

  function clearDeviceConnectionStates() {
    deviceConnectionStates.value = {}
  }

  function clearConnectTimeout(capability: string) {
    const timeoutHandle = connectTimeoutHandles.get(capability)
    if (timeoutHandle !== undefined) {
      clearTimeout(timeoutHandle)
      connectTimeoutHandles.delete(capability)
    }
  }

  function clearConnectTimeouts() {
    for (const timeoutHandle of connectTimeoutHandles.values()) {
      clearTimeout(timeoutHandle)
    }

    connectTimeoutHandles.clear()
  }

  function clearConnectTracking() {
    clearConnectTimeouts()
    connectTargets.value = {}
    connectedTargets.value = {}
    failedTargets.value = {}
    connectStopRequested = false
  }

  function hasConnectTargets(): boolean {
    return Object.keys(connectTargets.value).length > 0
  }

  function allConnectTargetsConnected(): boolean {
    const capabilities = Object.keys(connectTargets.value)
    return capabilities.length > 0 && capabilities.every((capability) => connectedTargets.value[capability] === true)
  }

  function allConnectTargetsFailed(): boolean {
    const capabilities = Object.keys(connectTargets.value)
    return capabilities.length > 0 && capabilities.every((capability) => failedTargets.value[capability] === true)
  }

  function requestConnectStop() {
    if (connectStopRequested) {
      return
    }

    connectStopRequested = true
    connectStopRequestToken.value += 1
  }

  function markCapabilityFailed(capability: string, mac: string) {
    if (connectTargets.value[capability] !== mac || connectedTargets.value[capability] === true) {
      return
    }

    failedTargets.value = {
      ...failedTargets.value,
      [capability]: true,
    }

    setDeviceConnectionState(mac, 'offline')

    if (allConnectTargetsFailed()) {
      requestConnectStop()
    }
  }

  function handleConnectTimeout(capability: string, mac: string) {
    markCapabilityFailed(capability, mac)
  }

  function scheduleConnectTimeout(capability: string, mac: string, timeoutMs: number) {
    clearConnectTimeout(capability)
    connectTimeoutHandles.set(capability, setTimeout(() => {
      connectTimeoutHandles.delete(capability)
      handleConnectTimeout(capability, mac)
    }, timeoutMs))
  }

  // EEG connects via a serial COM port and has its own internal retry logic inside the EXE.
  // A UI-side timer is not appropriate for it: it can legitimately take longer than any fixed
  // timeout (e.g. 79+ seconds in practice). Only BLE capabilities (ECG, blood_pressure) need
  // a UI timer because BLE scans have a defined duration and either find the device or not.
  const BLE_TIMEOUT_CAPABILITIES = new Set(['ecg', 'blood_pressure'])

  function initializeConnectTracking(targets: Record<string, string>) {
    const device = useDeviceStore()

    clearConnectTracking()
    connectTargets.value = { ...targets }

    for (const [capability, mac] of Object.entries(targets)) {
      if (BLE_TIMEOUT_CAPABILITIES.has(capability)) {
        scheduleConnectTimeout(capability, mac, device.getConnectTimeoutMs(mac))
      }
    }
  }

  function markCapabilityConnected(capability: string) {
    const mac = connectTargets.value[capability]
    if (mac === undefined) {
      return
    }

    clearConnectTimeout(capability)
    if (connectedTargets.value[capability] !== true) {
      connectedTargets.value = {
        ...connectedTargets.value,
        [capability]: true,
      }
    }

    setDeviceConnectionState(mac, 'online')

    isConnecting.value = false
    connectReadyToken.value += 1
    clearConnectTracking()
  }

  function getDeviceConnectionState(mac: string | null): DeviceConnectionState | null {
    if (mac === null) {
      return null
    }

    return deviceConnectionStates.value[mac] ?? null
  }

  function isDeviceOffline(mac: string | null): boolean {
    return getDeviceConnectionState(mac) === 'offline'
  }

  function handleStatus(event: BodyMonitorStatusEvent) {
    exeState.value = event.state
    activeRunId.value = event.runId ?? activeRunId.value
    activeCommandLine.value = event.commandLine ?? activeCommandLine.value

    if (event.sessionState !== undefined) {
      bodyMonitorState.value = event.sessionState
      isConnecting.value = event.sessionState === 'starting'

      if (event.sessionState === 'idle') {
        clearConnectTracking()
      }
    }

    if (event.state === 'idle') {
      activeRunId.value = null
      activeCommandLine.value = ''
      bodyMonitorState.value = 'idle'
      isScanning.value = false
      isConnecting.value = false
      chartData.value = createEmptyChartSnapshot()
      scanStartedAtMs.value = null
      stopElapsedTimer()
      clearConnectTracking()
    }
  }

  function handleStarted(event: BodyMonitorStartedEvent) {
    activeRunId.value = event.runId
    activeCommandLine.value = event.commandLine
    if (event.params.includes('--server')) {
      exeState.value = 'running'
      if (isScanning.value && scanCommandLine.value === '') {
        scanCommandLine.value = event.commandLine
      }
      return
    }
    bodyMonitorState.value = 'running'
    if (isConnecting.value) {
      scanCommandLine.value = event.commandLine
    }
  }

  function handleScanCommand(event: BodyMonitorScanCommandEvent) {
    activeRunId.value = event.runId
    activeCommandLine.value = event.commandLine
    if (event.cmd === 'list_devices' && isScanning.value) {
      scanCommandLine.value = event.commandLine
    }
  }

  function handleOutput(event: BodyMonitorOutputEvent) {
    if (activeRunId.value !== null && event.runId !== activeRunId.value) return
    rawLines.value.push(event.line)
    if (rawLines.value.length > RAW_LINES_MAX) {
      rawLines.value = rawLines.value.slice(-RAW_LINES_MAX)
    }
    if (event.stream === 'stdout' && event.parsedJson !== undefined) {
      chartData.value = appendParsedOutputToLogChart(chartData.value, event.parsedJson)
    }

    const selectedEegMac = useDeviceStore().getSelectedMac('eeg')
    const runtimeDeviceState = parseRuntimeDeviceState(event.parsedJson, selectedEegMac)
    if (runtimeDeviceState !== null) {
      setDeviceConnectionState(runtimeDeviceState.mac, runtimeDeviceState.state)

      if (isConnecting.value && connectTargets.value[runtimeDeviceState.source] === runtimeDeviceState.mac) {
        if (runtimeDeviceState.state === 'online') {
          markCapabilityConnected(runtimeDeviceState.source)
        }

        if (runtimeDeviceState.state === 'offline') {
          markCapabilityFailed(runtimeDeviceState.source, runtimeDeviceState.mac)
        }
      }
    }

    if (isConnecting.value) {
      const connectedCapability = parseConnectedCapability(event.line, event.parsedJson)
      if (connectedCapability !== null) {
        markCapabilityConnected(connectedCapability)
      } else if (!hasConnectTargets() && isConnectReadyLine(event.line)) {
        isConnecting.value = false
        connectReadyToken.value += 1
        clearConnectTracking()
        return
      }
    }

    if (isScanning.value || isConnecting.value) {
      const parsedStatus = parseScanLine(event.line)
      if (isScanning.value) {
        scanStatus.value = {
          ...parsedStatus,
          elapsedSec: getScanElapsedSec(),
        }
        return
      }

      scanStatus.value = parsedStatus
    }
  }

  function handleExit(event: BodyMonitorExitEvent) {
    if (event.runId === activeRunId.value) {
      activeRunId.value = null
    }
    exeState.value = 'idle'
    bodyMonitorState.value = 'idle'
    chartData.value = createEmptyChartSnapshot()
    if (isScanning.value) {
      scanStatus.value = { key: 'error', message: lastError.value ?? 'BodyMonitor server stopped' }
      isScanning.value = false
      scanDone.value = false
      scanStartedAtMs.value = null
      stopElapsedTimer()
    }
    if (isConnecting.value) {
      isConnecting.value = false
    }
    clearConnectTracking()
  }

  function handleError(event: BodyMonitorErrorEvent) {
    lastError.value = event.message
  }

  function handleStdioAck(event: BodyMonitorStdioAckEvent) {
    if (!event.ok) {
      if (event.error) {
        lastError.value = event.error
      }

      if (event.cmd === 'list_devices') {
        bodyMonitorState.value = 'idle'
        isScanning.value = false
        scanDone.value = false
        scanStartedAtMs.value = null
        const translatedStatus = event.error ? parsePlainStatus(event.error) : null
        scanStatus.value = translatedStatus ?? { key: 'error', message: event.error ?? 'list_devices failed' }
        stopElapsedTimer()
      }

      if (event.cmd === 'start') {
        bodyMonitorState.value = 'idle'
        isConnecting.value = false
        clearConnectTracking()
      }

      return
    }

    switch (event.cmd) {
      case 'list_devices': {
        const device = useDeviceStore()
        bodyMonitorState.value = 'idle'
        scanStatus.value = { key: 'complete', deviceCount: device.deviceCount }
        isScanning.value = false
        scanDone.value = true
        scanStartedAtMs.value = null
        stopElapsedTimer()
        break
      }
      case 'start':
        bodyMonitorState.value = 'running'
        break
      case 'stop':
        bodyMonitorState.value = 'idle'
        isConnecting.value = false
        clearConnectTracking()
        break
      case 'quit':
        bodyMonitorState.value = 'idle'
        isConnecting.value = false
        clearConnectTracking()
        break
    }
  }

  function handleStdioReady() {
    if (exeState.value === 'idle') {
      exeState.value = 'running'
    }
  }

  function resetOutputState() {
    scanStatus.value = null
    scanCommandLine.value = ''
    connectReadyToken.value = 0
  }

  function clearRawLines() {
    rawLines.value = []
    resetOutputState()
  }

  function clearChartData() {
    chartData.value = createEmptyChartSnapshot()
  }

  function beginScan(aCommandLine = '') {
    isScanning.value = true
    isConnecting.value = false
    scanDone.value = false
    chartData.value = createEmptyChartSnapshot()
    clearDeviceConnectionStates()
    if (bodyMonitorState.value === 'running' || bodyMonitorState.value === 'starting') {
      bodyMonitorState.value = 'stopping'
    }
    scanStatus.value = { key: 'progress', elapsedSec: 0 }
    scanCommandLine.value = aCommandLine !== '' ? aCommandLine : activeCommandLine.value
    scanStartedAtMs.value = Date.now()
    startElapsedTimer()
    refreshScanElapsedSec()
  }

  function beginConnect(aCommandLine: string) {
    const device = useDeviceStore()
    const targets: Record<string, string> = { ...device.connectTargets }

    isConnecting.value = true
    isScanning.value = false
    scanStatus.value = null
    connectReadyToken.value = 0
    chartData.value = createEmptyChartSnapshot()
    clearDeviceConnectionStates()
    initializeConnectTracking(targets)
    scanCommandLine.value = aCommandLine
    bodyMonitorState.value = 'starting'
    scanStartedAtMs.value = null
    stopElapsedTimer()
  }

  return {
    exeState,
    bodyMonitorState,
    activeRunId,
    rawLines,
    chartData,
    lastError,
    scanStatus,
    scanCommandLine,
    isScanning,
    isConnecting,
    connectReadyToken,
    connectStopRequestToken,
    scanDone,
    deviceConnectionStates,
    canStart,
    canScan,
    canStop,
    stateColor,
    getDeviceConnectionState,
    isDeviceOffline,
    handleStatus,
    handleStarted,
    handleScanCommand,
    handleOutput,
    handleExit,
    handleError,
    handleStdioAck,
    handleStdioReady,
    resetOutputState,
    clearRawLines,
    clearChartData,
    beginScan,
    beginConnect
  }
})

