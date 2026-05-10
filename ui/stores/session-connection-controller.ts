import { computed, ref, type Ref } from 'vue'
import type {
  BodyMonitorErrorEvent,
  BodyMonitorExitEvent,
  BodyMonitorOutputEvent,
  BodyMonitorScanCommandEvent,
  BodyMonitorScanDeviceStatusEvent,
  BodyMonitorStartedEvent,
  BodyMonitorState,
  BodyMonitorStatusEvent,
  BodyMonitorStdioAckEvent,
  LogChartDataSnapshot,
} from '@protocol'
import { appendParsedOutputToLogChart, createEmptyChartSnapshot } from '../../../SharedPasCore/ts/log-chart'
import { useDeviceStore } from './device'

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

export interface RuntimeDeviceStateTransition {
  readonly mac: string
  readonly state: DeviceConnectionState
  readonly source: 'ecg' | 'eeg'
}

interface CreateSessionConnectionControllerOptions {
  readonly exeState: Ref<BodyMonitorState>
  readonly bodyMonitorState: Ref<BodyMonitorState>
  readonly activeRunId: Ref<string | null>
  readonly activeCommandLine: Ref<string>
  readonly rawLines: Ref<string[]>
  readonly chartData: Ref<LogChartDataSnapshot>
  readonly lastError: Ref<string | null>
  readonly isBleConnectFailureEvent: (value: unknown) => boolean
  readonly isBleScanDeviceStatusJson: (value: unknown) => boolean
  readonly isConnectReadyLine: (line: string) => boolean
  readonly parseConnectedCapability: (line: string, parsedJson: unknown) => string | null
  readonly parsePlainStatus: (line: string) => ScanStatus | null
  readonly parseRuntimeDeviceState: (value: unknown, selectedEegMac: string | null) => RuntimeDeviceStateTransition | null
  readonly parseScanLine: (line: string) => ScanStatus
  readonly createScanDeviceStatus: (event: BodyMonitorScanDeviceStatusEvent, elapsedSec: number) => ScanStatus
}

const RAW_LINES_MAX = 1000
const BLE_TIMEOUT_CAPABILITIES = new Set(['ecg', 'blood_pressure'])

export function createSessionConnectionController(options: CreateSessionConnectionControllerOptions) {
  const scanStatus = ref<ScanStatus | null>(null)
  const scanCommandLine = ref('')
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
    options.exeState.value === 'running' &&
    options.bodyMonitorState.value === 'idle' &&
    !isScanning.value &&
    !isConnecting.value,
  )

  const canScan = computed(() =>
    options.exeState.value === 'running' &&
    !isScanning.value &&
    !isConnecting.value,
  )

  const canStop = computed(() => options.bodyMonitorState.value === 'running' || options.bodyMonitorState.value === 'starting')

  const stateColor = computed(() => {
    switch (options.bodyMonitorState.value) {
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

  function allConnectTargetsResolved(): boolean {
    const capabilities = Object.keys(connectTargets.value)
    return capabilities.length > 0 && capabilities.every((capability) => {
      return connectedTargets.value[capability] === true || failedTargets.value[capability] === true
    })
  }

  function hasFailedConnectTargets(): boolean {
    return Object.values(failedTargets.value).some((value) => value === true)
  }

  function requestConnectStop() {
    if (connectStopRequested) {
      return
    }

    connectStopRequested = true
    connectStopRequestToken.value += 1
  }

  function finalizeConnectIfResolved() {
    if (allConnectTargetsConnected()) {
      isConnecting.value = false
      connectReadyToken.value += 1
      clearConnectTracking()
      return
    }

    if (allConnectTargetsResolved() && hasFailedConnectTargets()) {
      requestConnectStop()
    }
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
    finalizeConnectIfResolved()
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
    finalizeConnectIfResolved()
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
    options.exeState.value = event.state
    options.activeRunId.value = event.runId ?? options.activeRunId.value
    options.activeCommandLine.value = event.commandLine ?? options.activeCommandLine.value

    if (event.sessionState !== undefined) {
      options.bodyMonitorState.value = event.sessionState
      isConnecting.value = event.sessionState === 'starting'

      if (event.sessionState === 'idle') {
        clearDeviceConnectionStates()
        clearConnectTracking()
      }
    }

    if (event.state === 'idle') {
      options.activeRunId.value = null
      options.activeCommandLine.value = ''
      options.bodyMonitorState.value = 'idle'
      isScanning.value = false
      isConnecting.value = false
      options.chartData.value = createEmptyChartSnapshot()
      clearDeviceConnectionStates()
      scanStartedAtMs.value = null
      stopElapsedTimer()
      clearConnectTracking()
    }
  }

  function handleStarted(event: BodyMonitorStartedEvent) {
    options.activeRunId.value = event.runId
    options.activeCommandLine.value = event.commandLine
    if (event.params.includes('--server')) {
      options.exeState.value = 'running'
      if (isScanning.value && scanCommandLine.value === '') {
        scanCommandLine.value = event.commandLine
      }
      return
    }

    options.bodyMonitorState.value = 'running'
    if (isConnecting.value) {
      scanCommandLine.value = event.commandLine
    }
  }

  function handleScanCommand(event: BodyMonitorScanCommandEvent) {
    options.activeRunId.value = event.runId
    options.activeCommandLine.value = event.commandLine
    if (event.cmd === 'list_devices' && isScanning.value) {
      scanCommandLine.value = event.commandLine
    }
  }

  function handleOutput(event: BodyMonitorOutputEvent) {
    if (options.activeRunId.value !== null && event.runId !== options.activeRunId.value) {
      return
    }

    options.rawLines.value.push(event.line)
    if (options.rawLines.value.length > RAW_LINES_MAX) {
      options.rawLines.value = options.rawLines.value.slice(-RAW_LINES_MAX)
    }

    if (event.stream === 'stdout' && event.parsedJson !== undefined) {
      options.chartData.value = appendParsedOutputToLogChart(options.chartData.value, event.parsedJson)
    }

    if (options.isBleScanDeviceStatusJson(event.parsedJson)) {
      return
    }

    const selectedEegMac = useDeviceStore().getSelectedMac('eeg')
    const runtimeDeviceState = options.parseRuntimeDeviceState(event.parsedJson, selectedEegMac)
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
      const connectedCapability = options.parseConnectedCapability(event.line, event.parsedJson)
      if (connectedCapability !== null) {
        markCapabilityConnected(connectedCapability)
      } else if (connectTargets.value.ecg !== undefined && options.isBleConnectFailureEvent(event.parsedJson)) {
        markCapabilityFailed('ecg', connectTargets.value.ecg)
      } else if (!hasConnectTargets() && options.isConnectReadyLine(event.line)) {
        isConnecting.value = false
        connectReadyToken.value += 1
        clearConnectTracking()
        return
      }
    }

    if (isScanning.value || isConnecting.value) {
      const parsedStatus = options.parseScanLine(event.line)
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
    if (event.runId === options.activeRunId.value) {
      options.activeRunId.value = null
    }

    options.exeState.value = 'idle'
    options.bodyMonitorState.value = 'idle'
    options.chartData.value = createEmptyChartSnapshot()
    clearDeviceConnectionStates()

    if (isScanning.value) {
      scanStatus.value = { key: 'error', message: options.lastError.value ?? 'BodyMonitor server stopped' }
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
    options.lastError.value = event.message
  }

  function handleStdioAck(event: BodyMonitorStdioAckEvent) {
    if (!event.ok) {
      if (event.error) {
        options.lastError.value = event.error
      }

      if (event.cmd === 'list_devices') {
        options.bodyMonitorState.value = 'idle'
        isScanning.value = false
        scanDone.value = false
        scanStartedAtMs.value = null
        const translatedStatus = event.error ? options.parsePlainStatus(event.error) : null
        scanStatus.value = translatedStatus ?? { key: 'error', message: event.error ?? 'list_devices failed' }
        stopElapsedTimer()
      }

      if (event.cmd === 'start') {
        options.bodyMonitorState.value = 'idle'
        isConnecting.value = false
        clearConnectTracking()
      }

      return
    }

    switch (event.cmd) {
      case 'list_devices': {
        const device = useDeviceStore()
        options.bodyMonitorState.value = 'idle'
        clearDeviceConnectionStates()
        scanStatus.value = { key: 'complete', deviceCount: device.deviceCount }
        isScanning.value = false
        scanDone.value = true
        scanStartedAtMs.value = null
        stopElapsedTimer()
        break
      }
      case 'start':
        options.bodyMonitorState.value = 'running'
        break
      case 'stop':
        options.bodyMonitorState.value = 'idle'
        isConnecting.value = false
        clearDeviceConnectionStates()
        clearConnectTracking()
        break
      case 'quit':
        options.bodyMonitorState.value = 'idle'
        isConnecting.value = false
        clearDeviceConnectionStates()
        clearConnectTracking()
        break
    }
  }

  function handleScanDeviceStatus(event: BodyMonitorScanDeviceStatusEvent) {
    if (!isScanning.value) {
      return
    }

    scanStatus.value = options.createScanDeviceStatus(event, getScanElapsedSec())
  }

  function handleStdioReady() {
    if (options.exeState.value === 'idle') {
      options.exeState.value = 'running'
    }
  }

  function resetOutputState() {
    scanStatus.value = null
    scanCommandLine.value = ''
    connectReadyToken.value = 0
  }

  function clearRawLines() {
    options.rawLines.value = []
    resetOutputState()
  }

  function clearChartData() {
    options.chartData.value = createEmptyChartSnapshot()
  }

  function beginScan(commandLine = '') {
    isScanning.value = true
    isConnecting.value = false
    scanDone.value = false
    options.chartData.value = createEmptyChartSnapshot()
    clearDeviceConnectionStates()
    if (options.bodyMonitorState.value === 'running' || options.bodyMonitorState.value === 'starting') {
      options.bodyMonitorState.value = 'stopping'
    }

    scanStatus.value = { key: 'progress', elapsedSec: 0 }
    scanCommandLine.value = commandLine !== '' ? commandLine : options.activeCommandLine.value
    scanStartedAtMs.value = Date.now()
    startElapsedTimer()
    refreshScanElapsedSec()
  }

  function beginConnect(commandLine: string) {
    const device = useDeviceStore()
    const targets: Record<string, string> = { ...device.connectTargets }

    isConnecting.value = true
    isScanning.value = false
    scanStatus.value = null
    connectReadyToken.value = 0
    options.chartData.value = createEmptyChartSnapshot()
    clearDeviceConnectionStates()
    initializeConnectTracking(targets)
    scanCommandLine.value = commandLine
    options.bodyMonitorState.value = 'starting'
    scanStartedAtMs.value = null
    stopElapsedTimer()
  }

  return {
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
    handleScanDeviceStatus,
    handleStdioReady,
    resetOutputState,
    clearRawLines,
    clearChartData,
    beginScan,
    beginConnect,
  }
}