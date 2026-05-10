<template>
  <div v-if="visible" class="eeg-status-badge row items-center q-gutter-x-sm">
    <q-icon :name="icon" :color="color" size="18px" :class="{ 'eeg-status-badge__spin': spinning }" />
    <span :class="['text-caption', `text-${color}`]">{{ label }}</span>
    <q-tooltip v-if="tooltip">{{ tooltip }}</q-tooltip>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useDeviceStore } from '../stores/device'
import { useEegDiagnosticsStore, type EegDiagnosticsStatusKey } from '../stores/eeg-diagnostics'

const { t } = useI18n()
const device = useDeviceStore()
const eegDiagnostics = useEegDiagnosticsStore()

const selectedMac = computed(() => device.getSelectedMac('eeg'))

const statusKey = computed<EegDiagnosticsStatusKey>(() => {
  const mac = selectedMac.value
  if (mac === null) return 'hidden'
  return eegDiagnostics.getStatusKey(mac)
})

const visible = computed(() => statusKey.value !== 'hidden')

interface StatusDisplay {
  icon: string
  color: string
  labelKey: string
  spinning?: boolean
}

const STATUS_MAP: Record<EegDiagnosticsStatusKey, StatusDisplay> = {
  hidden:     { icon: 'circle', color: 'grey-5', labelKey: 'eegDiagnostics.status.hidden' },
  checking:   { icon: 'sync', color: 'grey-5', labelKey: 'eegDiagnostics.status.checking', spinning: true },
  ready:      { icon: 'check_circle_outline', color: 'info', labelKey: 'eegDiagnostics.status.ready' },
  connected:  { icon: 'check_circle', color: 'positive', labelKey: 'eegDiagnostics.status.connected' },
  reconnected:{ icon: 'check_circle', color: 'positive', labelKey: 'eegDiagnostics.status.reconnected' },
  retrying:   { icon: 'sync', color: 'warning', labelKey: 'eegDiagnostics.status.retrying', spinning: true },
  stale:      { icon: 'warning', color: 'warning', labelKey: 'eegDiagnostics.status.stale' },
  offline:    { icon: 'link_off', color: 'negative', labelKey: 'eegDiagnostics.status.offline' },
  com_missing:{ icon: 'usb_off', color: 'negative', labelKey: 'eegDiagnostics.status.comMissing' },
  ble_missing:{ icon: 'bluetooth_disabled', color: 'negative', labelKey: 'eegDiagnostics.status.bleMissing' },
  error:      { icon: 'error_outline', color: 'negative', labelKey: 'eegDiagnostics.status.error' },
}

const display = computed(() => STATUS_MAP[statusKey.value])
const icon = computed(() => display.value.icon)
const color = computed(() => display.value.color)
const spinning = computed(() => display.value.spinning === true)
const label = computed(() => {
  const mac = selectedMac.value
  if (mac === null) return ''

  const state = eegDiagnostics.getState(mac)
  const key = statusKey.value

  if (key === 'retrying' && state.runtime.connectPort !== null) {
    return t('eegDiagnostics.status.retryingPort', { port: state.runtime.connectPort })
  }

  if (key === 'offline' && state.runtime.connectErrorCode !== null) {
    return t('eegDiagnostics.status.offlineError', { code: state.runtime.connectErrorCode })
  }

  if (key === 'com_missing' && state.diagnostics?.ble !== undefined) {
    return state.diagnostics.ble.ok
      ? t('eegDiagnostics.status.comMissingBleSeen')
      : t('eegDiagnostics.status.comMissing')
  }

  return t(display.value.labelKey)
})

const tooltip = computed<string | null>(() => {
  const mac = selectedMac.value
  if (mac === null) return null

  const state = eegDiagnostics.getState(mac)
  if (state.diagnostics?.message !== undefined) {
    return state.diagnostics.message
  }

  return null
})
</script>

<style scoped>
.eeg-status-badge {
  display: inline-flex;
  align-items: center;
}

.eeg-status-badge__spin {
  animation: spin 1.2s linear infinite;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to   { transform: rotate(360deg); }
}
</style>
