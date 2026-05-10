import { computed, onBeforeUnmount, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { LogChartDataSnapshot } from '@protocol'
import { EEG_BAND_KEYS } from '../services/eeg-band-snapshot'
import { useChartDataSource } from './use-chart-data-source'
import { useDeviceStore } from '../stores/device'
import { useSessionStore } from '../stores/session'

const LIVE_EEG_SAMPLE_TTL_MS = 10000

function getLatestEegBandTimestampMs(snapshot: LogChartDataSnapshot): number | null {
  let latestTimestampMs: number | null = null

  for (const bandKey of EEG_BAND_KEYS) {
    const series = snapshot.series.find((entry) => entry.key === bandKey)
    const latestPoint = series?.points.at(-1)
    if (latestPoint === undefined) {
      continue
    }

    latestTimestampMs = latestTimestampMs === null
      ? latestPoint[0]
      : Math.max(latestTimestampMs, latestPoint[0])
  }

  return latestTimestampMs
}

export function useLiveEegCalibrationState(resolveDeviceMac: () => string | null | undefined) {
  const { t } = useI18n()
  const device = useDeviceStore()
  const session = useSessionStore()
  const { liveChartData } = useChartDataSource()

  const nowMs = ref(Date.now())
  const tickInterval = setInterval(() => { nowMs.value = Date.now() }, 1000)
  onBeforeUnmount(() => clearInterval(tickInterval))

  const selectedEegMac = computed(() => device.getSelectedMac('eeg'))
  const targetDeviceMac = computed(() => {
    const rawMac = resolveDeviceMac()
    if (rawMac === undefined || rawMac === null) {
      return selectedEegMac.value
    }

    const trimmedMac = rawMac.trim()
    return trimmedMac === '' ? selectedEegMac.value : trimmedMac
  })

  const latestBandTimestampMs = computed(() => getLatestEegBandTimestampMs(liveChartData.value))
  const hasFreshLiveEegData = computed(() => {
    if (session.bodyMonitorState !== 'running' || session.isConnecting || session.isScanning) {
      return false
    }

    const latestTimestampMs = latestBandTimestampMs.value
    return latestTimestampMs !== null && (nowMs.value - latestTimestampMs) <= LIVE_EEG_SAMPLE_TTL_MS
  })

  const startBlockReason = computed(() => {
    if (selectedEegMac.value === null || targetDeviceMac.value === null || selectedEegMac.value !== targetDeviceMac.value) {
      return t('monitoring.calibration.noDevice')
    }

    if (session.isConnecting || session.bodyMonitorState === 'starting') {
      return t('calibration.liveEegConnecting')
    }

    if (!hasFreshLiveEegData.value) {
      return t('calibration.liveEegRequired')
    }

    return null
  })

  const isDeviceOffline = computed(() => {
    if (targetDeviceMac.value === null) {
      return false
    }

    return session.isDeviceOffline(targetDeviceMac.value)
  })

  const chartEmptyHintText = computed(() => startBlockReason.value ?? t('monitoring.chartEmptyTitle'))
  const canStartCalibration = computed(() => startBlockReason.value === null)
  const isWaitingForCalibration = computed(() => {
    return selectedEegMac.value !== null &&
      targetDeviceMac.value !== null &&
      selectedEegMac.value === targetDeviceMac.value &&
      !canStartCalibration.value
  })

  return {
    canStartCalibration,
    chartEmptyHintText,
    isDeviceOffline,
    isWaitingForCalibration,
    startBlockReason,
  }
}