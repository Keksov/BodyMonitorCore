import { defineStore } from 'pinia'
import { ref } from 'vue'
import type {
  BodyMonitorState,
  BodyMonitorScanDeviceStatusEvent,
} from '@protocol'
import { createEmptyChartSnapshot } from '../../../SharedPasCore/ts/log-chart'
import {
  createSessionConnectionController,
  type RuntimeDeviceStateTransition,
  type ScanStatus,
} from './session-connection-controller'

export type { DeviceConnectionState, ScanStatus } from './session-connection-controller'

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

function isBleScanDeviceStatusJson(value: unknown): boolean {
  return isRecord(value) && value.event === 'ble_scan_device'
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

function isBleConnectFailureEvent(value: unknown): boolean {
  if (!isRecord(value)) {
    return false
  }

  if (value.event !== 'ble_scan' || value.level !== 'error' || typeof value.message !== 'string') {
    return false
  }

  return value.message === 'ERROR: No Heart Rate device found.'
    || value.message === 'ERROR: Failed to connect to cached Heart Rate device.'
    || value.message === 'ERROR: Failed to subscribe to Heart Rate notifications.'
    || value.message === 'ERROR: Heart Rate Measurement characteristic not found.'
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

function parseRuntimeDeviceState(value: unknown, selectedEegMac: string | null): RuntimeDeviceStateTransition | null {
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
  const activeCommandLine = ref('')
  const connection = createSessionConnectionController({
    exeState,
    bodyMonitorState,
    activeRunId,
    activeCommandLine,
    rawLines,
    chartData,
    lastError,
    isBleConnectFailureEvent,
    isBleScanDeviceStatusJson,
    isConnectReadyLine,
    parseConnectedCapability,
    parsePlainStatus,
    parseRuntimeDeviceState,
    parseScanLine,
    createScanDeviceStatus(event, elapsedSec) {
      return createTranslatedStatus(
        'progress',
        'settings.statusProbeProgress',
        {
          completed: event.completedCount,
          total: event.totalCount,
        },
        {
          message: event.message,
          elapsedSec,
        },
      )
    },
  })

  return {
    exeState,
    bodyMonitorState,
    activeRunId,
    rawLines,
    chartData,
    lastError,
    scanStatus: connection.scanStatus,
    scanCommandLine: connection.scanCommandLine,
    isScanning: connection.isScanning,
    isConnecting: connection.isConnecting,
    connectReadyToken: connection.connectReadyToken,
    connectStopRequestToken: connection.connectStopRequestToken,
    scanDone: connection.scanDone,
    deviceConnectionStates: connection.deviceConnectionStates,
    canStart: connection.canStart,
    canScan: connection.canScan,
    canStop: connection.canStop,
    stateColor: connection.stateColor,
    getDeviceConnectionState: connection.getDeviceConnectionState,
    isDeviceOffline: connection.isDeviceOffline,
    handleStatus: connection.handleStatus,
    handleStarted: connection.handleStarted,
    handleScanCommand: connection.handleScanCommand,
    handleOutput: connection.handleOutput,
    handleExit: connection.handleExit,
    handleError: connection.handleError,
    handleStdioAck: connection.handleStdioAck,
    handleScanDeviceStatus: connection.handleScanDeviceStatus,
    handleStdioReady: connection.handleStdioReady,
    resetOutputState: connection.resetOutputState,
    clearRawLines: connection.clearRawLines,
    clearChartData: connection.clearChartData,
    beginScan: connection.beginScan,
    beginConnect: connection.beginConnect,
  }
})

