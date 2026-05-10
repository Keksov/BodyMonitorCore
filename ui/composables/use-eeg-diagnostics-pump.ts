import { computed, onUnmounted, ref, watch } from 'vue'
import { useDeviceStore } from '../stores/device'
import { useEegDiagnosticsStore } from '../stores/eeg-diagnostics'
import { useWs } from './use-ws'

const THROTTLE_MS = 12_000
const TRIGGER_STAGES = new Set(['hidden', 'checking', 'retrying', 'offline', 'stale', 'error', 'com_missing', 'ble_missing'])

/**
 * Auto-triggers EEG diagnostics when the selected EEG device is not connected.
 * Mount only from Settings and Monitoring surfaces.
 */
export function useEegDiagnosticsPump() {
  const ws = useWs()
  const device = useDeviceStore()
  const eegDiagnostics = useEegDiagnosticsStore()

  const lastTriggerMs = ref<Record<string, number>>({})
  let timer: ReturnType<typeof setTimeout> | null = null

  const selectedEegMac = computed(() => device.getSelectedMac('eeg'))

  function triggerDiagnose(mac: string): void {
    const now = Date.now()
    const last = lastTriggerMs.value[mac] ?? 0

    if (now - last < THROTTLE_MS) {
      return
    }

    lastTriggerMs.value = { ...lastTriggerMs.value, [mac]: now }
    eegDiagnostics.markLoading(mac)
    ws.send({ type: 'bodymonitor_server_diagnose_eeg', mac })
  }

  function maybeTrigger(): void {
    const mac = selectedEegMac.value
    if (mac === null) {
      return
    }

    const statusKey = eegDiagnostics.getStatusKey(mac)
    if (!TRIGGER_STAGES.has(statusKey)) {
      return
    }

    triggerDiagnose(mac)
  }

  function scheduleNext(): void {
    if (timer !== null) {
      clearTimeout(timer)
    }

    timer = setTimeout(() => {
      maybeTrigger()
      scheduleNext()
    }, THROTTLE_MS)
  }

  // Trigger immediately when the selected MAC changes or on mount
  const stopWatch = watch(
    selectedEegMac,
    (mac) => {
      if (mac !== null) {
        maybeTrigger()
      }
    },
    { immediate: true },
  )

  scheduleNext()

  onUnmounted(() => {
    stopWatch()
    if (timer !== null) {
      clearTimeout(timer)
      timer = null
    }
  })

  return {
    triggerDiagnose,
    selectedEegMac,
  }
}
