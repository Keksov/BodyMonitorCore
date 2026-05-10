import { computed, ref, watch } from 'vue'
import { useDeviceStore } from '../stores/device'
import { useSessionStore } from '../stores/session'
import { useBodyMonitorSessionStarter } from './use-bodymonitor-session-starter'
import { useWs } from './use-ws'

export function useAutoStartLiveEegMonitoring(resolveDeviceMac: () => string | null | undefined) {
  const device = useDeviceStore()
  const session = useSessionStore()
  const { startMonitoring } = useBodyMonitorSessionStarter()
  const ws = useWs()
  const attemptedTargetMac = ref<string | null>(null)

  const selectedEegMac = computed(() => device.getSelectedMac('eeg'))
  const targetDeviceMac = computed(() => {
    const rawMac = resolveDeviceMac()
    if (rawMac === undefined || rawMac === null) {
      return selectedEegMac.value
    }

    const trimmedMac = rawMac.trim()
    return trimmedMac === '' ? selectedEegMac.value : trimmedMac
  })

  watch(targetDeviceMac, (nextTargetMac, previousTargetMac) => {
    if (nextTargetMac !== previousTargetMac) {
      attemptedTargetMac.value = null
    }
  })

  watch(() => [
    targetDeviceMac.value,
    selectedEegMac.value,
    device.getConnectableMac('eeg'),
    ws.connectionState.value,
    session.bodyMonitorState,
    session.isConnecting ? '1' : '0',
    session.isScanning ? '1' : '0',
  ].join('|'), () => {
    const targetMac = targetDeviceMac.value
    if (targetMac === null) {
      return
    }

    if (selectedEegMac.value !== targetMac) {
      return
    }

    if (device.getConnectableMac('eeg') !== targetMac) {
      return
    }

    if (ws.connectionState.value !== 'connected') {
      return
    }

    if (session.bodyMonitorState !== 'idle' || session.isConnecting || session.isScanning) {
      return
    }

    if (attemptedTargetMac.value === targetMac) {
      return
    }

    if (startMonitoring(['eeg'])) {
      attemptedTargetMac.value = targetMac
    }
  }, { immediate: true })
}