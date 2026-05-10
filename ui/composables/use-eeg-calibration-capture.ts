import { onBeforeUnmount, ref } from 'vue'
import {
  useDeviceStore,
  type CalibrationActivityId,
  type EegBandRangeMap,
  type EegCalibrationModeStats,
  EEG_CALIBRATION_MIN_ACCEPTED_SAMPLES,
  EEG_CALIBRATION_WARMUP_SEC,
} from '../stores/device'
import { useChartDataSource } from './use-chart-data-source'
import {
  EEG_BAND_KEYS,
  buildEegBandAveragesSnapshot,
  getLatestSeriesValue,
} from '../services/eeg-band-snapshot'

const SAMPLE_INTERVAL_MS = 1000
const DEFAULT_SAMPLE_WINDOW_SEC = 1

interface CaptureAccumulator {
  readonly minValues: Record<string, number>
  readonly maxValues: Record<string, number>
}

export interface BeginEegCalibrationCaptureOptions {
  readonly deviceMac?: string | null
  readonly warmupSec?: number
  readonly sampleWindowSec?: number
}

export interface FinalizeEegCalibrationCaptureOptions {
  readonly deviceMac?: string | null
  readonly durationSec: number
}

export type EegCalibrationCaptureFailureReason =
  | 'device-missing'
  | 'insufficient-samples'
  | 'invalid-band-ranges'

export interface EegCalibrationFinalizeResult {
  readonly ok: boolean
  readonly reason?: EegCalibrationCaptureFailureReason
  readonly acceptedSampleCount: number
  readonly minAcceptedSamples: number
}

function createAccumulator(): CaptureAccumulator {
  return {
    minValues: Object.fromEntries(EEG_BAND_KEYS.map((bandKey) => [bandKey, Number.POSITIVE_INFINITY])),
    maxValues: Object.fromEntries(EEG_BAND_KEYS.map((bandKey) => [bandKey, Number.NEGATIVE_INFINITY])),
  }
}

export function useEegCalibrationCapture(activityId: CalibrationActivityId) {
  const device = useDeviceStore()
  const { liveChartData } = useChartDataSource()

  const isCapturing = ref(false)
  const acceptedSampleCount = ref(0)

  let captureStartedAtMs = 0
  let captureDeviceMac: string | null = null
  let warmupSec = EEG_CALIBRATION_WARMUP_SEC
  let sampleWindowSec = DEFAULT_SAMPLE_WINDOW_SEC
  let sampleTimer: ReturnType<typeof setInterval> | null = null
  let accumulator = createAccumulator()

  function normalizeDeviceMac(value: string | null | undefined): string | null {
    if (value === undefined || value === null) {
      return null
    }

    const trimmed = value.trim()
    return trimmed === '' ? null : trimmed
  }

  function resolveTargetMac(explicitMac: string | null | undefined): string | null {
    const normalizedExplicitMac = normalizeDeviceMac(explicitMac)
    if (normalizedExplicitMac !== null) {
      return normalizedExplicitMac
    }

    return device.getSelectedMac('eeg')
  }

  function stopSampling(): void {
    if (sampleTimer !== null) {
      clearInterval(sampleTimer)
      sampleTimer = null
    }
  }

  function resetCaptureState(): void {
    stopSampling()
    isCapturing.value = false
    acceptedSampleCount.value = 0
    captureStartedAtMs = 0
    captureDeviceMac = null
    warmupSec = EEG_CALIBRATION_WARMUP_SEC
    sampleWindowSec = DEFAULT_SAMPLE_WINDOW_SEC
    accumulator = createAccumulator()
  }

  function collectSample(): void {
    if (!isCapturing.value) {
      return
    }

    if (Date.now() - captureStartedAtMs < warmupSec * 1000) {
      return
    }

    const snapshot = liveChartData.value
    const bandSnapshot = buildEegBandAveragesSnapshot(snapshot, sampleWindowSec)
    if (bandSnapshot === null) {
      return
    }

    const poorSignalValue = getLatestSeriesValue(snapshot, 'poorSignal', bandSnapshot.anchorTimestampMs)
    if (poorSignalValue === null || poorSignalValue > 0) {
      return
    }

    const hasWindowSamplesForAllBands = EEG_BAND_KEYS.every((bandKey) => bandSnapshot.sampleCounts[bandKey] > 0)
    if (!hasWindowSamplesForAllBands) {
      return
    }

    for (const bandKey of EEG_BAND_KEYS) {
      const bandValue = bandSnapshot.bandValues[bandKey]
      if (!Number.isFinite(bandValue)) {
        return
      }
    }

    for (const bandKey of EEG_BAND_KEYS) {
      const bandValue = bandSnapshot.bandValues[bandKey]
      accumulator.minValues[bandKey] = Math.min(accumulator.minValues[bandKey], bandValue)
      accumulator.maxValues[bandKey] = Math.max(accumulator.maxValues[bandKey], bandValue)
    }

    acceptedSampleCount.value += 1
  }

  function beginCapture(options: BeginEegCalibrationCaptureOptions = {}): void {
    resetCaptureState()

    captureDeviceMac = resolveTargetMac(options.deviceMac)
    warmupSec = Math.max(0, Math.trunc(options.warmupSec ?? EEG_CALIBRATION_WARMUP_SEC))
    sampleWindowSec = Math.max(1, Math.trunc(options.sampleWindowSec ?? DEFAULT_SAMPLE_WINDOW_SEC))

    captureStartedAtMs = Date.now()
    isCapturing.value = true

    sampleTimer = setInterval(() => {
      collectSample()
    }, SAMPLE_INTERVAL_MS)
  }

  function cancelCapture(): void {
    resetCaptureState()
  }

  function finalizeCapture(options: FinalizeEegCalibrationCaptureOptions): EegCalibrationFinalizeResult {
    stopSampling()

    const acceptedSampleCountSnapshot = acceptedSampleCount.value

    const fail = (reason: EegCalibrationCaptureFailureReason): EegCalibrationFinalizeResult => {
      resetCaptureState()
      return {
        ok: false,
        reason,
        acceptedSampleCount: acceptedSampleCountSnapshot,
        minAcceptedSamples: EEG_CALIBRATION_MIN_ACCEPTED_SAMPLES,
      }
    }

    const targetMac = resolveTargetMac(options.deviceMac ?? captureDeviceMac)
    if (targetMac === null) {
      return fail('device-missing')
    }

    if (acceptedSampleCount.value < EEG_CALIBRATION_MIN_ACCEPTED_SAMPLES) {
      return fail('insufficient-samples')
    }

    const bandRanges = {} as EegBandRangeMap
    for (const bandKey of EEG_BAND_KEYS) {
      const minValue = accumulator.minValues[bandKey]
      const maxValue = accumulator.maxValues[bandKey]
      if (!Number.isFinite(minValue) || !Number.isFinite(maxValue) || maxValue <= minValue) {
        return fail('invalid-band-ranges')
      }

      bandRanges[bandKey] = {
        min: minValue,
        max: maxValue,
      }
    }

    const modeStats: EegCalibrationModeStats = {
      version: 1,
      activityId,
      recordedAtMs: Date.now(),
      durationSec: Math.max(1, Math.trunc(options.durationSec)),
      acceptedSampleCount: acceptedSampleCount.value,
      bandRanges,
    }

    device.setEegCalibrationModeStats(targetMac, modeStats)
    resetCaptureState()
    return {
      ok: true,
      acceptedSampleCount: acceptedSampleCountSnapshot,
      minAcceptedSamples: EEG_CALIBRATION_MIN_ACCEPTED_SAMPLES,
    }
  }

  onBeforeUnmount(() => {
    resetCaptureState()
  })

  return {
    isCapturing,
    acceptedSampleCount,
    beginCapture,
    cancelCapture,
    finalizeCapture,
  }
}
