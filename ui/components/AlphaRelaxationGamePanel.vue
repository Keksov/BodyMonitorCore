<template>
  <q-card class="alpha-relaxation-panel">
    <q-card-section v-if="props.showHeader" class="alpha-relaxation-panel__header row items-start justify-between q-col-gutter-md">
      <div class="col">
        <div class="text-h6">{{ t('calibration.alphaRelaxation.title') }}</div>
        <div class="text-body2 text-grey-5">{{ t('calibration.alphaRelaxation.subtitle') }}</div>
        <div v-if="normalizedHeaderContext !== null" class="text-caption text-grey-6 q-mt-xs">
          {{ normalizedHeaderContext }}
        </div>
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

    <q-card-section class="alpha-relaxation-panel__body">
      <div class="alpha-relaxation-panel__visual-stage">
        <div class="alpha-relaxation-panel__phase text-overline">
          {{ phaseLabel }}
        </div>

        <div class="alpha-relaxation-panel__orb-stage">
          <div class="alpha-relaxation-panel__orb-halo" :style="orbHaloStyle" />
          <div class="alpha-relaxation-panel__orb" :style="orbStyle" />
        </div>

        <div class="alpha-relaxation-panel__timer">{{ countdownLabel }}</div>
        <div class="alpha-relaxation-panel__cycles text-caption text-grey-5">
          {{ t('calibration.alphaRelaxation.status.cycles', { count: completedCycleCount }) }}
        </div>
        <div class="alpha-relaxation-panel__audio-state text-caption" :class="audioStateClassName">
          {{ audioStateLabel }}
        </div>
      </div>

      <div v-if="status === 'running'" class="alpha-relaxation-panel__eeg-chart-shell">
        <eeg-current-readings-chart
          class="alpha-relaxation-panel__eeg-chart"
          :data="activeChartData"
          :window-sec="1"
          scale-mode="normalized"
          :force-no-signal="isDeviceOffline"
          :empty-hint-text="chartEmptyHintText"
          compact
        />
      </div>

      <template v-if="status !== 'running'">
        <div class="alpha-relaxation-panel__settings-grid q-mt-lg">
          <q-input
            outlined
            dense
            dark
            color="white"
            type="number"
            min="1"
            step="1"
            :model-value="selectedDurationMin"
            :label="t('calibration.alphaRelaxation.controls.durationLabel')"
            @update:model-value="onDurationInput"
          />

          <q-toggle
            :model-value="audioEnabled"
            color="white"
            keep-color
            :label="t('calibration.alphaRelaxation.controls.soundLabel')"
            @update:model-value="onAudioEnabledInput"
          />
        </div>

        <div class="text-body2 text-grey-5 q-mt-md">
          {{ t('calibration.alphaRelaxation.instructionsBody') }}
        </div>

        <ul class="alpha-relaxation-panel__instruction-list">
          <li>{{ t('calibration.alphaRelaxation.instructionsRuleBreath') }}</li>
          <li>{{ t('calibration.alphaRelaxation.instructionsRuleGaze') }}</li>
          <li>{{ t('calibration.alphaRelaxation.instructionsRuleAudio') }}</li>
        </ul>

        <div v-if="status === 'finished' && currentSummary !== null" class="alpha-relaxation-panel__summary-block q-mt-lg">
          <div class="text-subtitle1">{{ t('calibration.alphaRelaxation.finishedTitle') }}</div>
          <div class="text-body2 text-grey-5 q-mt-xs">{{ t('calibration.alphaRelaxation.finishedSubtitle') }}</div>
          <div class="text-caption text-grey-4 q-mt-md">{{ t('calibration.alphaRelaxation.summaryLabel') }}</div>
          <div class="text-body1 q-mt-xs">{{ summaryMetrics(currentSummary) }}</div>
        </div>

        <div v-else-if="previousSummary !== null" class="alpha-relaxation-panel__summary-block q-mt-lg">
          <div class="text-subtitle2">{{ t('calibration.alphaRelaxation.previousRunTitle') }}</div>
          <div class="text-caption text-grey-5 q-mt-xs">
            {{ t('calibration.alphaRelaxation.previousRunAt', { time: formatSummaryTime(previousSummary.recordedAtMs) }) }}
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

    <q-card-actions align="right" class="alpha-relaxation-panel__footer">
      <q-btn
        v-if="showCloseButton"
        flat
        :label="t('calibration.actions.close')"
        @click="onClose"
      />
      <q-btn
        v-if="status === 'running'"
        flat
        color="white"
        :label="t('calibration.actions.stop')"
        @click="onStopGame"
      />
      <q-btn
        v-else-if="status === 'finished'"
        color="white"
        text-color="black"
        :label="t('calibration.actions.restart')"
        :disable="!canStartCalibration"
        @click="onStartGame"
      />
      <q-btn
        v-else
        color="white"
        text-color="black"
        :label="t('calibration.actions.start')"
        :disable="!canStartCalibration"
        :loading="isWaitingForCalibration"
        @click="onStartGame"
      />
    </q-card-actions>
  </q-card>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch, type CSSProperties } from 'vue'
import { useI18n } from 'vue-i18n'
import EegCurrentReadingsChart from './EegCurrentReadingsChart.vue'
import type { AlphaRelaxationSummary } from '../stores/device'
import { useAutoStartLiveEegMonitoring } from '../composables/use-auto-start-live-eeg-monitoring'
import { useAlphaRelaxationGame } from '../composables/use-alpha-relaxation-game'
import { useChartDataSource } from '../composables/use-chart-data-source'
import {
  useEegCalibrationCapture,
  type EegCalibrationFinalizeResult,
} from '../composables/use-eeg-calibration-capture'
import { useLiveEegCalibrationState } from '../composables/use-live-eeg-calibration-state'
import { useWs } from '../composables/use-ws'

const props = withDefaults(defineProps<{
  readonly previousSummary: AlphaRelaxationSummary | null
  readonly deviceMac?: string | null
  readonly headerContext?: string | null
  readonly showCloseButton?: boolean
  readonly showHeader?: boolean
}>(), {
  deviceMac: null,
  headerContext: null,
  showCloseButton: false,
  showHeader: true,
})

const emit = defineEmits<{
  (event: 'close'): void
  (event: 'clear'): void
  (event: 'save', value: AlphaRelaxationSummary): void
}>()

interface AlphaRelaxationStoredSettings {
  readonly durationMin: number
  readonly audioEnabled: boolean
}

const ALPHA_RELAXATION_SETTINGS_KEY = 'alphaRelaxationSettings'
const DEFAULT_DURATION_MIN = 1
const DEFAULT_AUDIO_ENABLED = true

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

function sanitizeAudioEnabled(value: unknown): boolean {
  return typeof value === 'boolean' ? value : DEFAULT_AUDIO_ENABLED
}

function buildAlphaRelaxationStoredSettings(
  value: Partial<AlphaRelaxationStoredSettings> | null | undefined
): AlphaRelaxationStoredSettings {
  return {
    durationMin: sanitizeDurationMin(value?.durationMin),
    audioEnabled: sanitizeAudioEnabled(value?.audioEnabled),
  }
}

function readStoredAlphaRelaxationSettings(): AlphaRelaxationStoredSettings {
  if (typeof localStorage === 'undefined') {
    return buildAlphaRelaxationStoredSettings(null)
  }

  const raw = localStorage.getItem(ALPHA_RELAXATION_SETTINGS_KEY)
  if (raw === null) {
    return buildAlphaRelaxationStoredSettings(null)
  }

  try {
    const parsed = JSON.parse(raw)
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return buildAlphaRelaxationStoredSettings(null)
    }

    return buildAlphaRelaxationStoredSettings(parsed as Partial<AlphaRelaxationStoredSettings>)
  } catch {
    return buildAlphaRelaxationStoredSettings(null)
  }
}

const { t } = useI18n()
const { send } = useWs()
const { activeChartData } = useChartDataSource()
const eegCapture = useEegCalibrationCapture('alphaRelaxation')
const {
  canStartCalibration,
  chartEmptyHintText,
  isDeviceOffline,
  isWaitingForCalibration,
  startBlockReason,
} = useLiveEegCalibrationState(() => props.deviceMac)
useAutoStartLiveEegMonitoring(() => props.deviceMac)
const storedSettings = readStoredAlphaRelaxationSettings()

const {
  status,
  phase,
  breathScale,
  secondsRemaining,
  completedCycleCount,
  currentSummary,
  startGame,
  stopGame,
} = useAlphaRelaxationGame()

const audioEnabled = ref(storedSettings.audioEnabled)
const audioRequested = ref(false)
const audioStartFailed = ref(false)
const selectedDurationMin = ref(storedSettings.durationMin)
const eegFinalizeWarning = ref<string | null>(null)

const normalizedHeaderContext = computed(() => {
  if (props.headerContext === null) {
    return null
  }

  const trimmed = props.headerContext.trim()
  return trimmed === '' ? null : trimmed
})

const countdownLabel = computed(() => {
  const totalSeconds = secondsRemaining.value
  const minutes = Math.floor(totalSeconds / 60)
  const seconds = totalSeconds % 60
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
})

const phaseLabel = computed(() => {
  if (status.value !== 'running') {
    return t('calibration.alphaRelaxation.phaseReady')
  }

  return t(`calibration.alphaRelaxation.phases.${phase.value}`)
})

const audioStateLabel = computed(() => {
  if (audioStartFailed.value) {
    return t('calibration.alphaRelaxation.status.audioStartFailed')
  }

  if (!audioEnabled.value) {
    return t('calibration.alphaRelaxation.status.audioOff')
  }

  if (audioRequested.value) {
    return t('calibration.alphaRelaxation.status.audioOn')
  }

  return t('calibration.alphaRelaxation.status.audioPending')
})

const audioStateClassName = computed(() => {
  if (audioStartFailed.value) {
    return 'text-negative'
  }

  return audioRequested.value ? 'text-positive' : 'text-grey-5'
})

const orbStyle = computed<CSSProperties>(() => {
  const currentScale = breathScale.value
  const gradient = phase.value === 'inhale'
    ? 'radial-gradient(circle at 35% 35%, rgba(210,245,255,0.95) 0%, rgba(76,180,212,0.72) 42%, rgba(11,43,61,0.08) 100%)'
    : 'radial-gradient(circle at 35% 35%, rgba(255,240,199,0.95) 0%, rgba(228,170,77,0.72) 42%, rgba(59,35,11,0.08) 100%)'

  return {
    transform: `scale(${currentScale.toFixed(3)})`,
    background: gradient,
  }
})

const orbHaloStyle = computed<CSSProperties>(() => {
  const opacity = 0.22 + ((breathScale.value - 0.56) / 0.44) * 0.3
  const haloColor = phase.value === 'inhale' ? '76, 180, 212' : '228, 170, 77'

  return {
    opacity: String(Math.max(0.18, Math.min(0.52, opacity))),
    boxShadow: `0 0 120px rgba(${haloColor}, 0.55)`,
  }
})

watch(currentSummary, (summary) => {
  if (summary === null) {
    return
  }

  const finalizeResult = eegCapture.finalizeCapture({
    deviceMac: props.deviceMac,
    durationSec: summary.durationSec,
  })
  eegFinalizeWarning.value = toEegFinalizeWarning(finalizeResult)
  emit('save', summary)
  requestAudioStop()
})

watch([selectedDurationMin, audioEnabled], ([durationMin, nextAudioEnabled]) => {
  const normalizedSettings = buildAlphaRelaxationStoredSettings({
    audioEnabled: nextAudioEnabled,
  })

  if (normalizedSettings.durationMin !== durationMin) {
    selectedDurationMin.value = normalizedSettings.durationMin
    return
  }

  if (normalizedSettings.audioEnabled !== nextAudioEnabled) {
    audioEnabled.value = normalizedSettings.audioEnabled
    return
  }

  if (typeof localStorage === 'undefined') {
    return
  }

  localStorage.setItem(ALPHA_RELAXATION_SETTINGS_KEY, JSON.stringify(normalizedSettings))
}, { immediate: true })

onBeforeUnmount(() => {
  eegCapture.cancelCapture()
  requestAudioStop()
  stopGame()
})

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

function onAudioEnabledInput(value: boolean | null): void {
  audioEnabled.value = value === true
}

function requestAudioStart(): void {
  audioStartFailed.value = false
  audioRequested.value = false

  if (!audioEnabled.value) {
    return
  }

  audioRequested.value = send({
    type: 'audio_alpha_relaxation_start',
    durationMin: selectedDurationMin.value,
  })
  audioStartFailed.value = !audioRequested.value
}

function requestAudioStop(): void {
  if (!audioRequested.value) {
    return
  }

  send({ type: 'audio_alpha_relaxation_stop' })
  audioRequested.value = false
}

function onStartGame(): void {
  eegFinalizeWarning.value = null
  eegCapture.beginCapture({ deviceMac: props.deviceMac })
  requestAudioStop()
  requestAudioStart()
  startGame({ durationMin: selectedDurationMin.value })
}

function onStopGame(): void {
  eegFinalizeWarning.value = null
  eegCapture.cancelCapture()
  requestAudioStop()
  stopGame()
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

function summaryMetrics(summary: AlphaRelaxationSummary): string {
  return t('calibration.alphaRelaxation.summaryMetrics', {
    minutes: Math.max(1, Math.round(summary.durationSec / 60)),
    cycles: summary.cyclesCompleted,
  })
}
</script>

<style scoped>
.alpha-relaxation-panel {
  background:
    radial-gradient(circle at top, rgba(56, 189, 248, 0.16), transparent 38%),
    radial-gradient(circle at bottom, rgba(245, 158, 11, 0.14), transparent 34%),
    #030712;
  color: #f8fafc;
}

.alpha-relaxation-panel__body {
  display: grid;
  gap: 20px;
}

.alpha-relaxation-panel__visual-stage {
  align-items: center;
  display: grid;
  gap: 8px;
  justify-items: center;
  text-align: center;
}

.alpha-relaxation-panel__phase {
  color: #cbd5e1;
  letter-spacing: 0.18em;
}

.alpha-relaxation-panel__orb-stage {
  align-items: center;
  display: grid;
  justify-items: center;
  min-height: clamp(220px, 42vh, 340px);
  position: relative;
  width: min(100%, 520px);
}

.alpha-relaxation-panel__orb-halo,
.alpha-relaxation-panel__orb {
  border-radius: 999px;
  position: absolute;
}

.alpha-relaxation-panel__orb-halo {
  height: clamp(180px, 28vw, 240px);
  transition: opacity 420ms ease;
  width: clamp(180px, 28vw, 240px);
}

.alpha-relaxation-panel__orb {
  box-shadow:
    0 0 30px rgba(255, 255, 255, 0.18),
    inset 0 0 36px rgba(255, 255, 255, 0.14);
  height: clamp(120px, 18vw, 160px);
  transition: transform 180ms linear, background 600ms ease;
  width: clamp(120px, 18vw, 160px);
}

.alpha-relaxation-panel__timer {
  font-size: clamp(2rem, 5vw, 3.4rem);
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  letter-spacing: 0.08em;
}

.alpha-relaxation-panel__audio-state {
  min-height: 1.25rem;
}

.alpha-relaxation-panel__eeg-chart-shell {
  background: rgba(15, 23, 42, 0.72);
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: 14px;
  min-height: 180px;
  padding: 8px;
}

.alpha-relaxation-panel__eeg-chart {
  min-height: 164px;
}

.alpha-relaxation-panel__settings-grid {
  align-items: center;
  display: grid;
  gap: 16px;
  grid-template-columns: minmax(0, 240px) auto;
}

.alpha-relaxation-panel__instruction-list {
  color: #94a3b8;
  margin: 12px 0 0;
  padding-left: 18px;
}

.alpha-relaxation-panel__instruction-list li + li {
  margin-top: 6px;
}

.alpha-relaxation-panel__summary-block {
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: 16px;
  padding: 16px;
  background: rgba(15, 23, 42, 0.72);
}

@media (max-width: 720px) {
  .alpha-relaxation-panel__settings-grid {
    grid-template-columns: 1fr;
  }
}
</style>