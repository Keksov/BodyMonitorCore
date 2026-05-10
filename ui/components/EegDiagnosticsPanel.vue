<template>
  <div class="eeg-diag-panel q-mt-sm">
    <div class="row items-center justify-between q-mb-xs">
      <span class="text-caption text-grey-5">{{ $t('eegDiagnostics.panel.title') }}</span>
      <q-btn
        flat
        dense
        round
        icon="refresh"
        size="sm"
        :loading="state.isLoading"
        :title="$t('eegDiagnostics.panel.checkNow')"
        @click="checkNow"
      />
    </div>

    <div class="eeg-diag-panel__rows">
      <!-- MAC -->
      <div class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.mac') }}</span>
        <span class="eeg-diag-panel__value text-caption text-mono">{{ props.mac }}</span>
      </div>

      <!-- BLE -->
      <div class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.bleStatus') }}</span>
        <span class="eeg-diag-panel__value text-caption">
          <template v-if="ble !== undefined">
            <q-icon :name="ble.ok ? 'bluetooth' : 'bluetooth_disabled'" :color="ble.ok ? 'positive' : 'negative'" size="14px" />
            {{ ble.ok ? (ble.identifier ?? $t('eegDiagnostics.panel.bleReachable')) : $t('eegDiagnostics.panel.bleUnreachable') }}
            <span v-if="ble.elapsedMs !== undefined" class="text-grey-5"> ({{ ble.elapsedMs }}ms)</span>
          </template>
          <span v-else class="text-grey-5">—</span>
        </span>
      </div>

      <!-- COM port -->
      <div class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.comPort') }}</span>
        <span class="eeg-diag-panel__value text-caption">
          <template v-if="com !== undefined">
            <q-icon :name="com.found ? 'usb' : 'usb_off'" :color="com.found ? 'positive' : 'negative'" size="14px" />
            {{ com.found ? (com.port ?? $t('eegDiagnostics.panel.comFound')) : $t('eegDiagnostics.panel.comNotFound') }}
          </template>
          <span v-else class="text-grey-5">—</span>
        </span>
      </div>

      <!-- COM description -->
      <div v-if="com?.description" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.comDescription') }}</span>
        <span class="eeg-diag-panel__value text-caption text-mono">{{ com.description }}</span>
      </div>

      <!-- PNPDeviceID -->
      <div v-if="com?.pnpDeviceId" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.pnpDeviceId') }}</span>
        <span class="eeg-diag-panel__value text-caption text-mono" style="word-break: break-all">{{ com.pnpDeviceId }}</span>
      </div>

      <!-- Runtime connect stage -->
      <div class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.connectStage') }}</span>
        <span class="eeg-diag-panel__value text-caption">
          {{ runtime.connectStage ?? '—' }}
        </span>
      </div>

      <!-- Active connect port -->
      <div v-if="runtime.connectPort" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.connectPort') }}</span>
        <span class="eeg-diag-panel__value text-caption text-mono">{{ runtime.connectPort }}</span>
      </div>

      <!-- Connect attempts -->
      <div v-if="runtime.connectAttempts > 0" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.connectAttempts') }}</span>
        <span class="eeg-diag-panel__value text-caption">{{ runtime.connectAttempts }}</span>
      </div>

      <!-- Last error code -->
      <div v-if="runtime.connectErrorCode !== null" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.connectError') }}</span>
        <span class="eeg-diag-panel__value text-caption text-negative">
          {{ runtime.connectErrorCode }}
          <span v-if="errorExplanation" class="text-grey-5"> — {{ errorExplanation }}</span>
        </span>
      </div>

      <!-- SDK version -->
      <div v-if="runtime.sdkVersion !== null" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.sdkVersion') }}</span>
        <span class="eeg-diag-panel__value text-caption">{{ runtime.sdkVersion }}</span>
      </div>

      <!-- Poor signal -->
      <div v-if="runtime.poorSignal !== null" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.poorSignal') }}</span>
        <span class="eeg-diag-panel__value text-caption">{{ runtime.poorSignal }}%</span>
      </div>

      <!-- EEG freshness -->
      <div v-if="runtime.lastEegSampleMs !== null" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.lastSampleAge') }}</span>
        <span class="eeg-diag-panel__value text-caption">{{ sampleAgeLabel }}</span>
      </div>

      <!-- Last check -->
      <div v-if="state.lastCheckMs !== null" class="eeg-diag-panel__row">
        <span class="eeg-diag-panel__label text-caption text-grey-5">{{ $t('eegDiagnostics.panel.lastCheck') }}</span>
        <span class="eeg-diag-panel__value text-caption">{{ lastCheckLabel }}</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useEegDiagnosticsStore } from '../stores/eeg-diagnostics'
import { useWs } from '../composables/use-ws'

const props = defineProps<{ mac: string }>()

const { t } = useI18n()
const eegDiagnostics = useEegDiagnosticsStore()
const ws = useWs()

const state = computed(() => eegDiagnostics.getState(props.mac))
const runtime = computed(() => state.value.runtime)
const ble = computed(() => state.value.diagnostics?.ble)
const com = computed(() => state.value.diagnostics?.com)

const ERROR_CODE_EXPLANATIONS: Record<number, string> = {
  '-1': 'TG_ERR_NOT_CONNECTED',
  '-2': 'COM port not ready (Windows SPP delay)',
  '-3': 'TG_ERR_NO_ERROR',
  '-100': 'TG_ERR_SYNCHRO_FAIL',
}

const errorExplanation = computed<string | null>(() => {
  const code = runtime.value.connectErrorCode
  if (code === null) return null
  return ERROR_CODE_EXPLANATIONS[code] ?? null
})

const sampleAgeLabel = computed<string>(() => {
  const ms = runtime.value.lastEegSampleMs
  if (ms === null) return '—'
  const ageSec = Math.round((Date.now() - ms) / 1000)
  return t('eegDiagnostics.panel.sampleAgeSec', { sec: ageSec })
})

const lastCheckLabel = computed<string>(() => {
  const ms = state.value.lastCheckMs
  if (ms === null) return '—'
  const ageSec = Math.round((Date.now() - ms) / 1000)
  return t('eegDiagnostics.panel.checkAgeSec', { sec: ageSec })
})

function checkNow(): void {
  eegDiagnostics.markLoading(props.mac)
  ws.send({ type: 'bodymonitor_server_diagnose_eeg', mac: props.mac })
}
</script>

<style scoped>
.eeg-diag-panel {
  border-top: 1px solid rgba(255, 255, 255, 0.07);
  padding-top: 8px;
}

.eeg-diag-panel__rows {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.eeg-diag-panel__row {
  display: flex;
  flex-direction: row;
  gap: 8px;
  align-items: flex-start;
}

.eeg-diag-panel__label {
  flex: 0 0 140px;
  text-align: right;
  opacity: 0.7;
}

.eeg-diag-panel__value {
  flex: 1 1 0;
  word-break: break-word;
  white-space: nowrap;
}

.text-mono {
  font-family: monospace;
}
</style>
