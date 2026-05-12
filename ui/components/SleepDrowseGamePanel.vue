<template>
  <q-card class="sleep-drowse-panel" :class="{ 'sleep-drowse-panel--running': status === 'running' }">
    <q-card-section v-if="props.showHeader" class="sleep-drowse-panel__header row items-start justify-between q-col-gutter-md">
      <div class="col">
        <div class="text-h6">{{ t('calibration.sleepDrowse.title') }}</div>
        <div class="text-body2 text-grey-5">{{ t('calibration.sleepDrowse.subtitle') }}</div>
      </div>

      <div v-if="showCloseButton" class="col-auto">
        <q-btn
          flat
          round
          dense
          icon="close"
          :aria-label="t('calibration.actions.close')"
          @click="onClose"
        />
      </div>
    </q-card-section>

    <q-separator v-if="props.showHeader" />

    <q-card-section class="sleep-drowse-panel__body">
      <div class="sleep-drowse-panel__stage">
        <div class="sleep-drowse-panel__phase text-overline">{{ phaseLabel }}</div>
        <div class="sleep-drowse-panel__timer">{{ countdownLabel }}</div>
        <div class="sleep-drowse-panel__audio-state text-caption" :class="audioStateClassName">
          {{ audioStateLabel }}
        </div>
      </div>

      <template v-if="status !== 'running'">
        <div class="sleep-drowse-panel__settings-grid q-mt-lg">
          <q-input
            outlined
            dense
            dark
            color="white"
            type="number"
            min="1"
            step="1"
            :model-value="selectedDurationMin"
            :label="t('calibration.sleepDrowse.controls.durationLabel')"
            @update:model-value="onDurationInput"
          />
        </div>

        <div class="text-body2 text-grey-5 q-mt-md">
          {{ t('calibration.sleepDrowse.instructionsBody') }}
        </div>

        <ul class="sleep-drowse-panel__instruction-list">
          <li>{{ t('calibration.sleepDrowse.instructionsRuleHeadphones') }}</li>
          <li>{{ t('calibration.sleepDrowse.instructionsRuleQuiet') }}</li>
          <li>{{ t('calibration.sleepDrowse.instructionsRuleDim') }}</li>
        </ul>

        <div v-if="status === 'finished' && currentSummary !== null" class="sleep-drowse-panel__summary-block q-mt-lg">
          <div class="text-subtitle1">{{ t('calibration.sleepDrowse.finishedTitle') }}</div>
          <div class="text-body2 text-grey-5 q-mt-xs">{{ t('calibration.sleepDrowse.finishedSubtitle') }}</div>
          <div class="text-caption text-grey-4 q-mt-md">{{ t('calibration.sleepDrowse.summaryLabel') }}</div>
          <div class="text-body1 q-mt-xs">{{ summaryMetrics(currentSummary) }}</div>
        </div>

        <div v-else-if="previousSummary !== null" class="sleep-drowse-panel__summary-block q-mt-lg">
          <div class="text-subtitle2">{{ t('calibration.sleepDrowse.previousRunTitle') }}</div>
          <div class="text-caption text-grey-5 q-mt-xs">
            {{ t('calibration.sleepDrowse.previousRunAt', { time: formatSummaryTime(previousSummary.recordedAtMs) }) }}
          </div>
          <div class="text-body2 text-grey-4 q-mt-sm">{{ summaryMetrics(previousSummary) }}</div>
          <q-btn
            flat
            dense
            color="white"
            class="q-mt-md"
            :label="t('calibration.actions.clearCalibration')"
            @click="emit('clear')"
          />
        </div>

        <div v-if="startBlockReason !== null" class="text-caption text-amber-4 q-mt-md">
          {{ startBlockReason }}
        </div>

        <div v-if="eegFinalizeWarning !== null" class="text-caption text-negative q-mt-sm">
          {{ eegFinalizeWarning }}
        </div>
      </template>
    </q-card-section>

    <q-card-actions v-if="status !== 'running'" align="right" class="sleep-drowse-panel__footer">
      <q-btn
        v-if="showCloseButton"
        flat
        :label="t('calibration.actions.close')"
        @click="onClose"
      />
      <q-btn
        color="white"
        text-color="black"
        :label="t('calibration.actions.start')"
        :disable="!canStartCalibration"
        :loading="isWaitingForCalibration"
        @click="onStartGame"
      />
    </q-card-actions>

    <div v-if="status === 'running'" class="sleep-drowse-panel__dim-overlay">
      <div class="sleep-drowse-panel__dim-stage">
        <div class="sleep-drowse-panel__dim-timer">{{ countdownLabel }}</div>
        <q-btn
          class="sleep-drowse-panel__dim-stop"
          color="white"
          text-color="black"
          unelevated
          rounded
          size="xl"
          :label="t('calibration.actions.stop')"
          @click="onStopGame"
        />
      </div>
    </div>

    <div v-if="status === 'running'" class="sleep-drowse-panel__running-eeg-chart">
      <eeg-current-readings-chart
        class="sleep-drowse-panel__eeg-chart"
        :data="activeChartData"
        :window-sec="1"
        data-correction="raw"
        :force-no-signal="isDeviceOffline"
        :empty-hint-text="chartEmptyHintText"
        show-signal-badge
        compact
      />
    </div>
  </q-card>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import EegCurrentReadingsChart from './EegCurrentReadingsChart.vue'
import type { DrowseCalibrationSummary } from '../stores/device'
import { useAutoStartLiveEegMonitoring } from '../composables/use-auto-start-live-eeg-monitoring'
import { useChartDataSource } from '../composables/use-chart-data-source'
import { useWs } from '../composables/use-ws'
import {
  useEegCalibrationCapture,
  type EegCalibrationFinalizeResult,
} from '../composables/use-eeg-calibration-capture'
import { useLiveEegCalibrationState } from '../composables/use-live-eeg-calibration-state'

const props = withDefaults(defineProps<{
  readonly previousSummary?: DrowseCalibrationSummary | null
  readonly deviceMac?: string | null
  readonly showCloseButton?: boolean
  readonly showHeader?: boolean
}>(), {
  previousSummary: null,
  deviceMac: null,
  showCloseButton: false,
  showHeader: true,
})

const emit = defineEmits<{
  (event: 'close'): void
  (event: 'clear'): void
  (event: 'save', value: DrowseCalibrationSummary): void
}>()

interface SleepDrowseStoredSettings {
  readonly durationMin: number
}

const SLEEP_DROWSE_SETTINGS_KEY = 'sleepDrowseSettings'
const DEFAULT_DURATION_MIN = 5

function sanitizeDurationMin(value: unknown): number {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value.trim())
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 1) {
    return DEFAULT_DURATION_MIN
  }

  return Math.max(1, Math.trunc(parsed))
}

function buildSleepDrowseStoredSettings(
  value: Partial<SleepDrowseStoredSettings> | null | undefined
): SleepDrowseStoredSettings {
  return {
    durationMin: sanitizeDurationMin(value?.durationMin),
  }
}

function readStoredSleepDrowseSettings(): SleepDrowseStoredSettings {
  if (typeof localStorage === 'undefined') {
    return buildSleepDrowseStoredSettings(null)
  }

  const raw = localStorage.getItem(SLEEP_DROWSE_SETTINGS_KEY)
  if (raw === null) {
    return buildSleepDrowseStoredSettings(null)
  }

  try {
    const parsed = JSON.parse(raw)
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return buildSleepDrowseStoredSettings(null)
    }

    return buildSleepDrowseStoredSettings(parsed as Partial<SleepDrowseStoredSettings>)
  } catch {
    return buildSleepDrowseStoredSettings(null)
  }
}

const { t } = useI18n()
const { send } = useWs()
const { activeChartData } = useChartDataSource()
const eegCapture = useEegCalibrationCapture('drowse')
const {
  canStartCalibration,
  chartEmptyHintText,
  isDeviceOffline,
  isWaitingForCalibration,
  startBlockReason,
} = useLiveEegCalibrationState(() => props.deviceMac)
useAutoStartLiveEegMonitoring(() => props.deviceMac)
const storedSettings = readStoredSleepDrowseSettings()

const status = ref<'idle' | 'running' | 'finished'>('idle')
const secondsRemaining = ref(0)
const selectedDurationMin = ref(storedSettings.durationMin)
const currentSummary = ref<DrowseCalibrationSummary | null>(null)
const eegFinalizeWarning = ref<string | null>(null)

let timerHandle: ReturnType<typeof setInterval> | null = null
const audioRequested = ref(false)
const audioStartFailed = ref(false)

const countdownLabel = computed(() => {
  const totalSeconds = Math.max(0, secondsRemaining.value)
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
})

const phaseLabel = computed(() => {
  if (status.value === 'running') {
    return t('calibration.sleepDrowse.phaseRunning')
  }
  if (status.value === 'finished') {
    return t('calibration.sleepDrowse.phaseFinished')
  }
  return t('calibration.sleepDrowse.phaseReady')
})

const audioStateLabel = computed(() => {
  if (audioStartFailed.value) {
    return t('calibration.sleepDrowse.status.audioStartFailed')
  }
  if (audioRequested.value) {
    return t('calibration.sleepDrowse.status.audioOn')
  }
  return t('calibration.sleepDrowse.status.audioPending')
})

const audioStateClassName = computed(() => {
  if (audioStartFailed.value) {
    return 'text-negative'
  }
  return audioRequested.value ? 'text-positive' : 'text-grey-5'
})

onBeforeUnmount(() => {
  stopTimer()
  requestAudioStop()
  eegCapture.cancelCapture()
})

watch(currentSummary, (summary) => {
  if (summary === null) {
    return
  }

  emit('save', summary)
})

watch(selectedDurationMin, (durationMin) => {
  const normalizedDurationMin = sanitizeDurationMin(durationMin)
  if (normalizedDurationMin !== durationMin) {
    selectedDurationMin.value = normalizedDurationMin
    return
  }

  if (typeof localStorage === 'undefined') {
    return
  }

  localStorage.setItem(
    SLEEP_DROWSE_SETTINGS_KEY,
    JSON.stringify(buildSleepDrowseStoredSettings({ durationMin: normalizedDurationMin }))
  )
}, { immediate: true })

function onDurationInput(value: string | number | null): void {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value.trim())
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 1) {
    return
  }

  selectedDurationMin.value = sanitizeDurationMin(parsed)
}

function startTimer(): void {
  stopTimer()
  secondsRemaining.value = selectedDurationMin.value * 60
  timerHandle = setInterval(() => {
    if (secondsRemaining.value <= 1) {
      secondsRemaining.value = 0
      stopTimer()
      requestAudioStop()
      status.value = 'finished'
      const summary: DrowseCalibrationSummary = {
        version: 1,
        activityId: 'drowse',
        recordedAtMs: Date.now(),
        durationSec: selectedDurationMin.value * 60,
      }
      currentSummary.value = summary
      const finalizeResult = eegCapture.finalizeCapture({
        deviceMac: props.deviceMac,
        durationSec: summary.durationSec,
      })
      eegFinalizeWarning.value = toEegFinalizeWarning(finalizeResult)
      return
    }
    secondsRemaining.value -= 1
  }, 1000)
}

function stopTimer(): void {
  if (timerHandle !== null) {
    clearInterval(timerHandle)
    timerHandle = null
  }
}

function requestAudioStart(): void {
  audioStartFailed.value = false
  audioRequested.value = false

  audioRequested.value = send({
    type: 'audio_sleep_drowse_start',
    durationMin: selectedDurationMin.value,
  })
  audioStartFailed.value = !audioRequested.value
}

function requestAudioStop(): void {
  if (!audioRequested.value) {
    return
  }

  send({ type: 'audio_sleep_drowse_stop' })
  audioRequested.value = false
}

function onStartGame(): void {
  eegFinalizeWarning.value = null
  currentSummary.value = null
  eegCapture.beginCapture({ deviceMac: props.deviceMac })
  requestAudioStop()
  requestAudioStart()
  status.value = 'running'
  startTimer()
}

function onStopGame(): void {
  eegFinalizeWarning.value = null
  stopTimer()
  requestAudioStop()
  eegCapture.cancelCapture()
  status.value = 'idle'
  secondsRemaining.value = 0
  currentSummary.value = null
}

function onClose(): void {
  onStopGame()
  emit('close')
}

function formatSummaryTime(recordedAtMs: number): string {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(recordedAtMs))
}

function summaryMetrics(summary: DrowseCalibrationSummary): string {
  return t('calibration.sleepDrowse.summaryMetrics', {
    minutes: Math.max(1, Math.round(summary.durationSec / 60)),
  })
}

function toEegFinalizeWarning(finalizeResult: EegCalibrationFinalizeResult): string | null {
  if (finalizeResult.ok) {
    return null
  }

  if (finalizeResult.reason === 'device-missing') {
    return t('calibration.eegCapture.deviceMissing')
  }

  if (finalizeResult.reason === 'insufficient-samples') {
    return t('calibration.eegCapture.insufficientSamples', {
      accepted: finalizeResult.acceptedSampleCount,
      required: finalizeResult.minAcceptedSamples,
    })
  }

  return t('calibration.eegCapture.invalidBandRanges')
}
</script>

<style scoped>
.sleep-drowse-panel {
  background:
    radial-gradient(circle at top, rgba(94, 129, 172, 0.18), transparent 38%),
    radial-gradient(circle at bottom, rgba(46, 52, 64, 0.32), transparent 36%),
    #02040a;
  color: #e5e9f0;
  position: relative;
  overflow: hidden;
}

.sleep-drowse-panel__body {
  display: grid;
  gap: 18px;
}

.sleep-drowse-panel__stage {
  align-items: center;
  display: grid;
  gap: 6px;
  justify-items: center;
  text-align: center;
  padding: 16px 0;
}

.sleep-drowse-panel__phase {
  color: #94a3b8;
  letter-spacing: 0.18em;
}

.sleep-drowse-panel__timer {
  font-size: clamp(2.4rem, 6vw, 4rem);
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  letter-spacing: 0.08em;
}

.sleep-drowse-panel__audio-state {
  min-height: 1.25rem;
}

.sleep-drowse-panel__settings-grid {
  align-items: center;
  display: grid;
  gap: 16px;
  grid-template-columns: minmax(0, 240px);
}

.sleep-drowse-panel__instruction-list {
  color: #94a3b8;
  margin: 12px 0 0;
  padding-left: 18px;
}

.sleep-drowse-panel__instruction-list li + li {
  margin-top: 6px;
}

.sleep-drowse-panel__summary-block {
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: 16px;
  padding: 16px;
  background: rgba(15, 23, 42, 0.72);
}

.sleep-drowse-panel__running-eeg-chart {
  background: rgba(3, 7, 18, 0.9);
  border-top: 1px solid rgba(148, 163, 184, 0.2);
  padding: 8px 12px 12px;
  pointer-events: none;
  position: relative;
  z-index: 6;
}

.sleep-drowse-panel__eeg-chart {
  min-height: 152px;
}

.sleep-drowse-panel__dim-overlay {
  position: absolute;
  inset: 0;
  background: rgba(2, 4, 10, 0.96);
  display: grid;
  place-items: center;
  z-index: 5;
  animation: sleep-drowse-dim-in 1.6s ease forwards;
}

.sleep-drowse-panel__dim-stage {
  display: grid;
  gap: 32px;
  justify-items: center;
  text-align: center;
  padding: 32px;
}

.sleep-drowse-panel__dim-timer {
  font-size: clamp(3rem, 9vw, 6rem);
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  letter-spacing: 0.1em;
  color: rgba(229, 233, 240, 0.55);
}

.sleep-drowse-panel__dim-stop {
  min-width: 220px;
  font-size: 1.2rem;
  letter-spacing: 0.06em;
}

@keyframes sleep-drowse-dim-in {
  from { background: rgba(2, 4, 10, 0.4); }
  to   { background: rgba(2, 4, 10, 0.98); }
}
</style>
