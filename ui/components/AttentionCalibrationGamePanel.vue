<template>
  <q-card class="attention-calibration-panel">
    <q-card-section v-if="props.showHeader" class="attention-calibration-panel__header row items-start justify-between q-col-gutter-md">
      <div class="col">
        <div class="text-h6">{{ t('calibration.attention.title') }}</div>
        <div class="text-body2 text-grey-6">{{ t('calibration.attention.subtitle') }}</div>
        <div v-if="normalizedHeaderContext !== null" class="text-caption text-grey-5 q-mt-xs">
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
          @click="emit('close')"
        />
      </div>
    </q-card-section>

    <q-separator v-if="props.showHeader" />

    <q-card-section class="attention-calibration-panel__body">
      <div v-if="status !== 'running'" class="attention-calibration-panel__settings-panel">
        <div class="text-subtitle2">{{ t('calibration.attention.difficultyTitle') }}</div>
        <div class="text-body2 text-grey-5">{{ t('calibration.attention.difficultyHint') }}</div>

        <div class="attention-calibration-panel__settings-grid q-mt-md">
          <q-input
            outlined
            dense
            dark
            color="white"
            type="number"
            min="1"
            step="1"
            :model-value="selectedDurationMin"
            :label="t('calibration.attention.durationLabel')"
            @update:model-value="onDurationInput"
          />

          <q-select
            v-model="selectedOperationPreset"
            outlined
            dense
            emit-value
            map-options
            options-dense
            dark
            color="white"
            dropdown-icon="expand_more"
            :label="t('calibration.attention.operationDifficultyLabel')"
            :options="operationPresetOptions"
          />

          <q-select
            v-model="selectedNumberScalePreset"
            outlined
            dense
            emit-value
            map-options
            options-dense
            dark
            color="white"
            dropdown-icon="expand_more"
            :label="t('calibration.attention.numberScaleLabel')"
            :options="numberScalePresetOptions"
          />

          <div class="attention-calibration-panel__settings-pair">
            <q-select
              v-model="selectedMovingShapesPct"
              outlined
              dense
              emit-value
              map-options
              options-dense
              dark
              color="white"
              dropdown-icon="expand_more"
              :label="t('calibration.attention.movingShapesLabel')"
              :options="movingShapesPctOptions"
            />

            <q-select
              v-model="selectedMovingSpeed"
              outlined
              dense
              emit-value
              map-options
              options-dense
              dark
              color="white"
              dropdown-icon="expand_more"
              :disable="selectedMovingShapesPct === 0"
              :label="t('calibration.attention.movingSpeedLabel')"
              :options="movingSpeedOptions"
            />
          </div>
        </div>
      </div>

      <template v-if="status === 'running'">
        <div class="attention-calibration-panel__running-top">
          <div class="attention-calibration-panel__stats-grid">
            <div class="attention-calibration-panel__stat-card">
              <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.timerLabel') }}</div>
              <div class="attention-calibration-panel__stat-value">{{ secondsRemaining }}</div>
            </div>

            <div class="attention-calibration-panel__stat-card">
              <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.completedLabel') }}</div>
              <div class="attention-calibration-panel__stat-value">{{ completedTargetCount }}</div>
            </div>

            <div class="attention-calibration-panel__stat-card attention-calibration-panel__stat-card--danger">
              <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.errorsLabel') }}</div>
              <div class="attention-calibration-panel__stat-value">{{ errorCount }}</div>
            </div>
          </div>

          <div class="attention-calibration-panel__target-block attention-calibration-panel__target-block--inline">
            <div class="text-caption text-grey-5">{{ t('calibration.attention.targetLabel') }}</div>
            <div class="text-subtitle1">
              {{ t('calibration.attention.targetHint', { number: expectedNumber, shape: requiredShapeLabel }) }}
            </div>
          </div>
        </div>

        <q-linear-progress
          rounded
          size="10px"
          color="white"
          track-color="grey-9"
          :value="countdownProgress"
        />

        <div class="attention-calibration-panel__eeg-chart-shell">
          <eeg-current-readings-chart
            class="attention-calibration-panel__eeg-chart"
            :data="activeChartData"
            :window-sec="1"
            scale-mode="normalized"
            :force-no-signal="isDeviceOffline"
            :empty-hint-text="chartEmptyHintText"
            compact
          />
        </div>

        <div ref="boardElement" class="attention-calibration-panel__board">
          <button
            v-for="token in visibleTokens"
            :key="token.id"
            type="button"
            :class="tokenClassNames(token)"
            :aria-label="tokenAriaLabel(token)"
            :style="tokenPlacementStyle(token)"
            @click="onTokenClick(token)"
          >
            <svg viewBox="0 0 100 100" class="attention-calibration-panel__token-svg" aria-hidden="true">
              <circle
                v-if="token.shape === 'circle'"
                class="attention-calibration-panel__token-shape"
                cx="50"
                cy="50"
                r="40"
              />
              <polygon
                v-else
                class="attention-calibration-panel__token-shape"
                points="50,10 12,88 88,88"
              />
              <text
                x="50"
                :y="tokenTextY(token)"
                text-anchor="middle"
                dominant-baseline="middle"
                :class="tokenNumberClassNames(token)"
                :style="tokenTextStyle(token)"
              >
                {{ token.expression }}
              </text>
            </svg>
          </button>
        </div>
      </template>

      <template v-else-if="status === 'finished' && currentSummary !== null">
        <div class="attention-calibration-panel__summary-block">
          <div>
            <div class="text-subtitle1">{{ t('calibration.attention.finishedTitle') }}</div>
            <div class="text-body2 text-grey-6">{{ t('calibration.attention.finishedSubtitle') }}</div>
          </div>

          <div class="attention-calibration-panel__stats-grid">
            <div class="attention-calibration-panel__stat-card">
              <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.completedLabel') }}</div>
              <div class="attention-calibration-panel__stat-value">{{ currentSummary.completedTargetCount }}</div>
            </div>

            <div class="attention-calibration-panel__stat-card attention-calibration-panel__stat-card--danger">
              <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.errorsLabel') }}</div>
              <div class="attention-calibration-panel__stat-value">{{ currentSummary.errorCount }}</div>
            </div>

            <div class="attention-calibration-panel__stat-card">
              <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.accuracyLabel') }}</div>
              <div class="attention-calibration-panel__stat-value">{{ accuracyLabel(currentSummary) }}</div>
            </div>
          </div>
        </div>
      </template>

      <template v-else>
        <div class="attention-calibration-panel__intro-block">
          <div class="attention-calibration-panel__intro-panel">
            <div class="text-subtitle1">{{ t('calibration.attention.instructionsTitle') }}</div>
            <div class="text-body2 text-grey-6 q-mt-sm">{{ t('calibration.attention.instructionsBody') }}</div>
            <ul class="attention-calibration-panel__instruction-list">
              <li>{{ t('calibration.attention.instructionsRuleOrder') }}</li>
              <li>{{ t('calibration.attention.instructionsRuleShape') }}</li>
              <li>{{ t('calibration.attention.instructionsRuleTime') }}</li>
            </ul>
          </div>

          <div v-if="previousSummary !== null" class="attention-calibration-panel__intro-panel">
            <div class="text-subtitle2">{{ t('calibration.attention.previousRunTitle') }}</div>
            <div class="text-caption text-grey-5 q-mt-xs">
              {{ t('calibration.attention.previousRunAt', { time: formatSummaryTime(previousSummary.recordedAtMs) }) }}
            </div>

            <div class="attention-calibration-panel__previous-stats row q-col-gutter-sm q-row-gutter-sm q-mt-sm">
              <div class="col-12 col-sm-4">
                <div class="attention-calibration-panel__stat-card attention-calibration-panel__stat-card--compact">
                  <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.completedLabel') }}</div>
                  <div class="attention-calibration-panel__stat-value">{{ previousSummary.completedTargetCount }}</div>
                </div>
              </div>

              <div class="col-12 col-sm-4">
                <div class="attention-calibration-panel__stat-card attention-calibration-panel__stat-card--compact attention-calibration-panel__stat-card--danger">
                  <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.errorsLabel') }}</div>
                  <div class="attention-calibration-panel__stat-value">{{ previousSummary.errorCount }}</div>
                </div>
              </div>

              <div class="col-12 col-sm-4">
                <div class="attention-calibration-panel__stat-card attention-calibration-panel__stat-card--compact">
                  <div class="attention-calibration-panel__stat-label">{{ t('calibration.attention.accuracyLabel') }}</div>
                  <div class="attention-calibration-panel__stat-value">{{ accuracyLabel(previousSummary) }}</div>
                </div>
              </div>
            </div>

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
        </div>
      </template>
    </q-card-section>

    <q-card-actions align="right" class="attention-calibration-panel__footer">
      <q-btn
        v-if="showCloseButton"
        flat
        :label="t('calibration.actions.close')"
        @click="emit('close')"
      />
      <q-btn
        v-if="status === 'finished'"
        color="white"
        text-color="black"
        :label="t('calibration.actions.restart')"
        :disable="!canStartCalibration"
        @click="onStartGame"
      />
      <q-btn
        v-else-if="status !== 'running'"
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
import { computed, nextTick, onBeforeUnmount, ref, watch, type CSSProperties } from 'vue'
import { useI18n } from 'vue-i18n'
import EegCurrentReadingsChart from './EegCurrentReadingsChart.vue'
import { useAutoStartLiveEegMonitoring } from '../composables/use-auto-start-live-eeg-monitoring'
import { useChartDataSource } from '../composables/use-chart-data-source'
import {
  useAttentionCalibrationGame,
  type AttentionCalibrationMovingSpeed,
  type AttentionCalibrationNumberScalePreset,
  type AttentionCalibrationOperationPreset,
  type AttentionCalibrationToken,
} from '../composables/use-attention-calibration-game'
import {
  useEegCalibrationCapture,
  type EegCalibrationFinalizeResult,
} from '../composables/use-eeg-calibration-capture'
import { useLiveEegCalibrationState } from '../composables/use-live-eeg-calibration-state'
import type { AttentionCalibrationSummary } from '../stores/device'

const props = withDefaults(defineProps<{
  readonly previousSummary: AttentionCalibrationSummary | null
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
  (event: 'save', value: AttentionCalibrationSummary): void
}>()

interface BoardMetrics {
  readonly width: number
  readonly height: number
}

interface BoardLayout {
  readonly columns: number
  readonly rows: number
  readonly slotCount: number
  readonly cellWidth: number
  readonly cellHeight: number
  readonly tokenSize: number
}

interface TokenPlacement {
  readonly slotIndex: number
  readonly offsetXRatio: number
  readonly offsetYRatio: number
}

interface AttentionCalibrationStoredSettings {
  readonly durationMin: number
  readonly operationPreset: AttentionCalibrationOperationPreset
  readonly numberScalePreset: AttentionCalibrationNumberScalePreset
  readonly movingShapesPct: number
  readonly movingSpeed: AttentionCalibrationMovingSpeed
}

const ATTENTION_CALIBRATION_SETTINGS_KEY = 'attentionCalibrationSettings'
const DEFAULT_DURATION_MIN = 2
const DEFAULT_OPERATION_PRESET: AttentionCalibrationOperationPreset = 'add-only'
const DEFAULT_NUMBER_SCALE_PRESET: AttentionCalibrationNumberScalePreset = 'small'
const DEFAULT_MOVING_SHAPES_PCT = 0
const DEFAULT_MOVING_SPEED: AttentionCalibrationMovingSpeed = 'medium'
const VALID_OPERATION_PRESETS: readonly AttentionCalibrationOperationPreset[] = ['add-only', 'add-subtract', 'add-subtract-multiply', 'all']
const VALID_NUMBER_SCALE_PRESETS: readonly AttentionCalibrationNumberScalePreset[] = ['small', 'small-large']
const VALID_MOVING_SHAPES_PCT: readonly number[] = [0, 25, 50, 75, 100]
const VALID_MOVING_SPEEDS: readonly AttentionCalibrationMovingSpeed[] = ['slow', 'medium', 'fast']

function clampPlacementRatio(value: number): number {
  return Math.max(0.08, Math.min(0.92, value))
}

function createPlacementOffset(): Pick<TokenPlacement, 'offsetXRatio' | 'offsetYRatio'> {
  return {
    offsetXRatio: clampPlacementRatio(0.08 + (Math.random() * 0.84)),
    offsetYRatio: clampPlacementRatio(0.08 + (Math.random() * 0.84)),
  }
}

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

function sanitizeOperationPreset(value: unknown): AttentionCalibrationOperationPreset {
  return typeof value === 'string' && (VALID_OPERATION_PRESETS as readonly string[]).includes(value)
    ? value as AttentionCalibrationOperationPreset
    : DEFAULT_OPERATION_PRESET
}

function sanitizeNumberScalePreset(value: unknown): AttentionCalibrationNumberScalePreset {
  return typeof value === 'string' && (VALID_NUMBER_SCALE_PRESETS as readonly string[]).includes(value)
    ? value as AttentionCalibrationNumberScalePreset
    : DEFAULT_NUMBER_SCALE_PRESET
}

function sanitizeMovingShapesPct(value: unknown): number {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value.trim())
      : Number.NaN

  if (!Number.isFinite(parsed)) {
    return DEFAULT_MOVING_SHAPES_PCT
  }

  const normalized = Math.max(0, Math.min(100, Math.trunc(parsed)))
  return VALID_MOVING_SHAPES_PCT.includes(normalized) ? normalized : DEFAULT_MOVING_SHAPES_PCT
}

function sanitizeMovingSpeed(value: unknown): AttentionCalibrationMovingSpeed {
  return typeof value === 'string' && (VALID_MOVING_SPEEDS as readonly string[]).includes(value)
    ? value as AttentionCalibrationMovingSpeed
    : DEFAULT_MOVING_SPEED
}

function buildAttentionCalibrationStoredSettings(
  value: Partial<AttentionCalibrationStoredSettings> | null | undefined
): AttentionCalibrationStoredSettings {
  return {
    durationMin: sanitizeDurationMin(value?.durationMin),
    operationPreset: sanitizeOperationPreset(value?.operationPreset),
    numberScalePreset: sanitizeNumberScalePreset(value?.numberScalePreset),
    movingShapesPct: sanitizeMovingShapesPct(value?.movingShapesPct),
    movingSpeed: sanitizeMovingSpeed(value?.movingSpeed),
  }
}

function readStoredAttentionCalibrationSettings(): AttentionCalibrationStoredSettings {
  if (typeof localStorage === 'undefined') {
    return buildAttentionCalibrationStoredSettings(null)
  }

  const raw = localStorage.getItem(ATTENTION_CALIBRATION_SETTINGS_KEY)
  if (raw === null) {
    return buildAttentionCalibrationStoredSettings(null)
  }

  try {
    const parsed = JSON.parse(raw)
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return buildAttentionCalibrationStoredSettings(null)
    }

    return buildAttentionCalibrationStoredSettings(parsed as Partial<AttentionCalibrationStoredSettings>)
  } catch {
    return buildAttentionCalibrationStoredSettings(null)
  }
}

function shuffleIndices(length: number): number[] {
  const indices = Array.from({ length }, (_, index) => index)

  for (let index = indices.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1))
    const currentValue = indices[index]
    indices[index] = indices[swapIndex]
    indices[swapIndex] = currentValue
  }

  return indices
}

function createBoardLayout(width: number, height: number, tokenCount: number): BoardLayout {
  if (width <= 0 || height <= 0 || tokenCount <= 0) {
    return {
      columns: 0,
      rows: 0,
      slotCount: 0,
      cellWidth: 0,
      cellHeight: 0,
      tokenSize: 0,
    }
  }

  const requestedSlotCount = tokenCount + Math.ceil(tokenCount / 2)
  let columns = Math.max(1, Math.ceil(Math.sqrt(requestedSlotCount)))
  let rows = Math.max(1, Math.ceil(requestedSlotCount / columns))

  while (columns > 1 && (columns - 1) * rows >= requestedSlotCount) {
    columns -= 1
    rows = Math.max(1, Math.ceil(requestedSlotCount / columns))
  }

  const cellWidth = width / columns
  const cellHeight = height / rows

  return {
    columns,
    rows,
    slotCount: columns * rows,
    cellWidth,
    cellHeight,
    tokenSize: Math.min(124, Math.min(cellWidth, cellHeight) * 0.78),
  }
}

const MOVING_SPEED_CONFIG: Record<AttentionCalibrationMovingSpeed, { intervalMs: number, transitionSec: number }> = {
  slow: { intervalMs: 4000, transitionSec: 3.5 },
  medium: { intervalMs: 2500, transitionSec: 2 },
  fast: { intervalMs: 1500, transitionSec: 1.2 },
}

const { t } = useI18n()
const { activeChartData } = useChartDataSource()
const eegCapture = useEegCalibrationCapture('attention')
const {
  canStartCalibration,
  chartEmptyHintText,
  isDeviceOffline,
  isWaitingForCalibration,
  startBlockReason,
} = useLiveEegCalibrationState(() => props.deviceMac)
useAutoStartLiveEegMonitoring(() => props.deviceMac)
const storedSettings = readStoredAttentionCalibrationSettings()
const {
  durationSec,
  status,
  secondsRemaining,
  expectedNumber,
  visibleTokens,
  errorCount,
  completedTargetCount,
  requiredShape,
  currentMovingShapesPct,
  currentMovingSpeed,
  finishedSummary,
  startGame,
  handleTokenClick,
  getTokenFlashState,
} = useAttentionCalibrationGame()

const lastSavedResultAtMs = ref<number | null>(null)
const boardElement = ref<HTMLElement | null>(null)
const boardMetrics = ref<BoardMetrics>({ width: 0, height: 0 })
const tokenPlacements = ref<Record<number, TokenPlacement>>({})
const selectedDurationMin = ref(storedSettings.durationMin)
const selectedOperationPreset = ref<AttentionCalibrationOperationPreset>(storedSettings.operationPreset)
const selectedNumberScalePreset = ref<AttentionCalibrationNumberScalePreset>(storedSettings.numberScalePreset)
const selectedMovingShapesPct = ref(storedSettings.movingShapesPct)
const selectedMovingSpeed = ref<AttentionCalibrationMovingSpeed>(storedSettings.movingSpeed)
const movingTokenIds = ref<Set<number>>(new Set())
const normalizedHeaderContext = computed(() => {
  const text = props.headerContext?.trim() ?? ''
  return text === '' ? null : text
})
const currentSummary = computed(() => finishedSummary.value)
const requiredShapeLabel = computed(() => t(`calibration.shapes.${requiredShape.value}`))
const operationPresetOptions = computed(() => {
  return [
    { label: t('calibration.attention.operationPresets.addOnly'), value: 'add-only' },
    { label: t('calibration.attention.operationPresets.addSubtract'), value: 'add-subtract' },
    { label: t('calibration.attention.operationPresets.addSubtractMultiply'), value: 'add-subtract-multiply' },
    { label: t('calibration.attention.operationPresets.all'), value: 'all' },
  ] satisfies Array<{ label: string, value: AttentionCalibrationOperationPreset }>
})
const numberScalePresetOptions = computed(() => {
  return [
    { label: t('calibration.attention.numberScalePresets.small'), value: 'small' },
    { label: t('calibration.attention.numberScalePresets.smallLarge'), value: 'small-large' },
  ] satisfies Array<{ label: string, value: AttentionCalibrationNumberScalePreset }>
})
const movingShapesPctOptions = computed(() => {
  return [
    { label: t('calibration.attention.movingShapesPctOptions.0'), value: 0 },
    { label: t('calibration.attention.movingShapesPctOptions.25'), value: 25 },
    { label: t('calibration.attention.movingShapesPctOptions.50'), value: 50 },
    { label: t('calibration.attention.movingShapesPctOptions.75'), value: 75 },
    { label: t('calibration.attention.movingShapesPctOptions.100'), value: 100 },
  ] satisfies Array<{ label: string, value: number }>
})
const movingSpeedOptions = computed(() => {
  return [
    { label: t('calibration.attention.movingSpeedOptions.slow'), value: 'slow' },
    { label: t('calibration.attention.movingSpeedOptions.medium'), value: 'medium' },
    { label: t('calibration.attention.movingSpeedOptions.fast'), value: 'fast' },
  ] satisfies Array<{ label: string, value: AttentionCalibrationMovingSpeed }>
})
const visibleTokenKey = computed(() => visibleTokens.value.map((token) => token.id).join(','))
const boardLayout = computed(() => {
  return createBoardLayout(boardMetrics.value.width, boardMetrics.value.height, visibleTokens.value.length)
})
const countdownProgress = computed(() => {
  return Math.max(0, Math.min(1, secondsRemaining.value / durationSec.value))
})
const movingTransitionSec = computed(() => MOVING_SPEED_CONFIG[currentMovingSpeed.value].transitionSec)
const eegFinalizeWarning = ref<string | null>(null)

let boardResizeObserver: ResizeObserver | null = null
let movingTimerHandle: ReturnType<typeof setInterval> | null = null

watch(finishedSummary, (summary) => {
  if (summary === null) {
    return
  }

  if (lastSavedResultAtMs.value === summary.recordedAtMs) {
    return
  }

  const finalizeResult = eegCapture.finalizeCapture({
    deviceMac: props.deviceMac,
    durationSec: summary.durationSec,
  })
  eegFinalizeWarning.value = toEegFinalizeWarning(finalizeResult)
  emit('save', summary)
  lastSavedResultAtMs.value = summary.recordedAtMs
})

watch(status, (nextStatus) => {
  if (nextStatus !== 'running') {
    tokenPlacements.value = {}
    stopMovingTimer()
    movingTokenIds.value = new Set()
  }
})

watch([
  selectedDurationMin,
  selectedOperationPreset,
  selectedNumberScalePreset,
  selectedMovingShapesPct,
  selectedMovingSpeed,
], ([durationMin, operationPreset, numberScalePreset, movingShapesPct, movingSpeed]) => {
  const normalizedSettings = buildAttentionCalibrationStoredSettings({
    durationMin,
    operationPreset,
    numberScalePreset,
    movingShapesPct,
    movingSpeed,
  })

  if (normalizedSettings.durationMin !== durationMin) {
    selectedDurationMin.value = normalizedSettings.durationMin
    return
  }

  if (normalizedSettings.operationPreset !== operationPreset) {
    selectedOperationPreset.value = normalizedSettings.operationPreset
    return
  }

  if (normalizedSettings.numberScalePreset !== numberScalePreset) {
    selectedNumberScalePreset.value = normalizedSettings.numberScalePreset
    return
  }

  if (normalizedSettings.movingShapesPct !== movingShapesPct) {
    selectedMovingShapesPct.value = normalizedSettings.movingShapesPct
    return
  }

  if (normalizedSettings.movingSpeed !== movingSpeed) {
    selectedMovingSpeed.value = normalizedSettings.movingSpeed
    return
  }

  if (typeof localStorage === 'undefined') {
    return
  }

  localStorage.setItem(ATTENTION_CALIBRATION_SETTINGS_KEY, JSON.stringify(normalizedSettings))
}, { immediate: true })

watch(boardElement, (element) => {
  if (boardResizeObserver !== null) {
    boardResizeObserver.disconnect()
    boardResizeObserver = null
  }

  if (element === null) {
    boardMetrics.value = { width: 0, height: 0 }
    return
  }

  syncBoardMetrics(element)

  if (typeof ResizeObserver === 'undefined') {
    return
  }

  boardResizeObserver = new ResizeObserver(() => {
    syncBoardMetrics(element)
  })
  boardResizeObserver.observe(element)
  void nextTick(() => {
    syncBoardMetrics(element)
  })
}, { flush: 'post' })

watch(() => `${visibleTokenKey.value}|${boardLayout.value.slotCount}`, () => {
  syncTokenPlacements()
  syncMovingTokenSet()
}, { immediate: true })

onBeforeUnmount(() => {
  eegCapture.cancelCapture()
  stopMovingTimer()
  if (boardResizeObserver !== null) {
    boardResizeObserver.disconnect()
  }
})

function resolveMovingTargetCount(): number {
  const tokenCount = visibleTokens.value.length
  if (tokenCount <= 0 || currentMovingShapesPct.value <= 0) {
    return 0
  }

  return Math.min(tokenCount, Math.max(1, Math.round((tokenCount * currentMovingShapesPct.value) / 100)))
}

function stopMovingTimer(): void {
  if (movingTimerHandle !== null) {
    clearInterval(movingTimerHandle)
    movingTimerHandle = null
  }
}

function applyMovingOffsets(): void {
  if (movingTokenIds.value.size <= 0 || boardLayout.value.slotCount <= 0) {
    return
  }

  const nextPlacements = { ...tokenPlacements.value }
  let hasChanges = false

  for (const tokenId of movingTokenIds.value) {
    const previousPlacement = nextPlacements[tokenId]
    if (previousPlacement === undefined) {
      continue
    }

    nextPlacements[tokenId] = {
      slotIndex: previousPlacement.slotIndex,
      ...createPlacementOffset(),
    }
    hasChanges = true
  }

  if (hasChanges) {
    tokenPlacements.value = nextPlacements
  }
}

function startMovingTimer(): void {
  stopMovingTimer()
  if (status.value !== 'running' || currentMovingShapesPct.value <= 0 || boardLayout.value.slotCount <= 0) {
    return
  }

  movingTimerHandle = setInterval(() => {
    applyMovingOffsets()
  }, MOVING_SPEED_CONFIG[currentMovingSpeed.value].intervalMs)
}

function syncMovingTokenSet(): void {
  const targetCount = resolveMovingTargetCount()
  if (status.value !== 'running' || boardLayout.value.slotCount <= 0 || targetCount <= 0) {
    stopMovingTimer()
    movingTokenIds.value = new Set()
    return
  }

  const visibleIds = visibleTokens.value.map((token) => token.id)
  const preservedIds = visibleIds
    .filter((tokenId) => movingTokenIds.value.has(tokenId))
    .slice(0, targetCount)
  const remainingIds = visibleIds.filter((tokenId) => !movingTokenIds.value.has(tokenId))
  const nextMovingIds = new Set<number>(preservedIds)

  for (const shuffledIndex of shuffleIndices(remainingIds.length)) {
    if (nextMovingIds.size >= targetCount) {
      break
    }

    nextMovingIds.add(remainingIds[shuffledIndex])
  }

  movingTokenIds.value = nextMovingIds

  if (nextMovingIds.size <= 0) {
    stopMovingTimer()
    return
  }

  if (movingTimerHandle === null) {
    startMovingTimer()
  }
}

function syncBoardMetrics(element: HTMLElement): void {
  const width = Math.round(element.clientWidth)
  const height = Math.round(element.clientHeight)
  if (width === boardMetrics.value.width && height === boardMetrics.value.height) {
    return
  }

  boardMetrics.value = { width, height }
}

function syncTokenPlacements(): void {
  const tokenIds = visibleTokens.value.map((token) => token.id)
  const slotCount = boardLayout.value.slotCount

  if (tokenIds.length === 0 || slotCount <= 0) {
    tokenPlacements.value = {}
    return
  }

  const usedSlots = new Set<number>()
  const nextPlacements: Record<number, TokenPlacement> = {}

  for (const tokenId of tokenIds) {
    const previousPlacement = tokenPlacements.value[tokenId]
    if (previousPlacement === undefined || previousPlacement.slotIndex >= slotCount || usedSlots.has(previousPlacement.slotIndex)) {
      continue
    }

    nextPlacements[tokenId] = {
      slotIndex: previousPlacement.slotIndex,
      offsetXRatio: clampPlacementRatio(previousPlacement.offsetXRatio),
      offsetYRatio: clampPlacementRatio(previousPlacement.offsetYRatio),
    }
    usedSlots.add(previousPlacement.slotIndex)
  }

  const freeSlots = shuffleIndices(slotCount).filter((slotIndex) => !usedSlots.has(slotIndex))
  for (const tokenId of tokenIds) {
    if (tokenId in nextPlacements) {
      continue
    }

    const freeSlotIndex = freeSlots.length <= 1 ? 0 : Math.floor(Math.random() * freeSlots.length)
    const [slotIndex = 0] = freeSlots.splice(freeSlotIndex, 1)

    nextPlacements[tokenId] = {
      slotIndex,
      ...createPlacementOffset(),
    }
  }

  tokenPlacements.value = nextPlacements
}

function onTokenClick(token: AttentionCalibrationToken): void {
  handleTokenClick(token)
}

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

function onStartGame(): void {
  stopMovingTimer()
  movingTokenIds.value = new Set()
  eegFinalizeWarning.value = null
  eegCapture.beginCapture({ deviceMac: props.deviceMac })
  startGame({
    durationMin: selectedDurationMin.value,
    operationPreset: selectedOperationPreset.value,
    numberScalePreset: selectedNumberScalePreset.value,
    movingShapesPct: selectedMovingShapesPct.value,
    movingSpeed: selectedMovingSpeed.value,
  })
}

function tokenClassNames(token: AttentionCalibrationToken): string[] {
  const classNames = [
    'attention-calibration-panel__token-button',
    `attention-calibration-panel__token-button--${token.shape}`,
  ]

  if (getTokenFlashState(token.id) === 'wrong') {
    classNames.push('attention-calibration-panel__token-button--wrong')
  }

  return classNames
}

function tokenNumberClassNames(token: AttentionCalibrationToken): string[] {
  const classNames = ['attention-calibration-panel__token-number']

  if (token.shape === 'triangle') {
    classNames.push('attention-calibration-panel__token-number--triangle')
  }

  if (token.expression.length >= 5) {
    classNames.push('attention-calibration-panel__token-number--compact')
  }

  return classNames
}

function tokenTextY(token: AttentionCalibrationToken): number {
  return token.shape === 'triangle' ? 63 : 51
}

function tokenTextStyle(token: AttentionCalibrationToken): CSSProperties {
  if (token.expression.length >= 6) {
    return { fontSize: '0.92rem' }
  }

  if (token.expression.length >= 5) {
    return { fontSize: '1.02rem' }
  }

  return {}
}

function tokenPlacementStyle(token: AttentionCalibrationToken): CSSProperties {
  const placement = tokenPlacements.value[token.id]
  if (placement === undefined || boardLayout.value.columns <= 0 || boardLayout.value.rows <= 0) {
    return {
      height: '0px',
      opacity: '0',
      pointerEvents: 'none',
      width: '0px',
    }
  }

  const column = placement.slotIndex % boardLayout.value.columns
  const row = Math.floor(placement.slotIndex / boardLayout.value.columns)
  const freeX = Math.max(0, boardLayout.value.cellWidth - boardLayout.value.tokenSize)
  const freeY = Math.max(0, boardLayout.value.cellHeight - boardLayout.value.tokenSize)

  const baseStyle = {
    height: `${Math.round(boardLayout.value.tokenSize)}px`,
    left: `${Math.round((column * boardLayout.value.cellWidth) + (freeX * placement.offsetXRatio))}px`,
    top: `${Math.round((row * boardLayout.value.cellHeight) + (freeY * placement.offsetYRatio))}px`,
    width: `${Math.round(boardLayout.value.tokenSize)}px`,
  }

  if (movingTokenIds.value.has(token.id)) {
    return {
      ...baseStyle,
      transition: `left ${movingTransitionSec.value}s ease-in-out, top ${movingTransitionSec.value}s ease-in-out`,
    }
  }

  return baseStyle
}

function tokenAriaLabel(token: AttentionCalibrationToken): string {
  return t('calibration.attention.tokenLabel', {
    expression: token.expression,
    number: token.number,
    shape: t(`calibration.shapes.${token.shape}`),
  })
}

function formatSummaryTime(recordedAtMs: number): string {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(recordedAtMs))
}

function accuracyLabel(summary: AttentionCalibrationSummary): string {
  const attempts = summary.completedTargetCount + summary.errorCount
  if (attempts <= 0) {
    return '0%'
  }

  return `${Math.round((summary.completedTargetCount / attempts) * 100)}%`
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
.attention-calibration-panel {
  background:
    radial-gradient(circle at 12% 18%, rgba(255, 56, 92, 0.24), transparent 28%),
    radial-gradient(circle at 86% 16%, rgba(0, 255, 136, 0.18), transparent 30%),
    radial-gradient(circle at 50% 100%, rgba(72, 126, 255, 0.28), transparent 40%),
    linear-gradient(180deg, rgba(6, 7, 15, 0.98), rgba(4, 5, 12, 0.94));
  border: 1px solid rgba(255, 255, 255, 0.18);
  box-shadow:
    0 18px 42px rgba(0, 0, 0, 0.46),
    0 0 24px rgba(255, 56, 92, 0.12),
    0 0 30px rgba(0, 255, 136, 0.1),
    0 0 38px rgba(72, 126, 255, 0.14);
}

.attention-calibration-panel__body {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.attention-calibration-panel__settings-panel {
  background: rgba(8, 10, 22, 0.6);
  border: 1px solid rgba(255, 255, 255, 0.16);
  border-radius: 14px;
  padding: 14px 16px;
}

.attention-calibration-panel__settings-grid {
  display: grid;
  gap: 12px;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
}

.attention-calibration-panel__settings-pair {
  display: grid;
  gap: 12px;
  grid-column: 1 / -1;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.attention-calibration-panel__settings-grid :deep(.q-field__control) {
  background: rgba(5, 7, 16, 0.9);
}

.attention-calibration-panel__settings-grid :deep(.q-field__label),
.attention-calibration-panel__settings-grid :deep(.q-field__native),
.attention-calibration-panel__settings-grid :deep(.q-field__marginal),
.attention-calibration-panel__settings-grid :deep(.q-field__input) {
  color: rgba(255, 255, 255, 0.92);
}

.attention-calibration-panel__stats-grid {
  display: grid;
  gap: 12px;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
}

.attention-calibration-panel__running-top {
  align-items: stretch;
  display: grid;
  gap: 12px;
  grid-template-columns: minmax(0, 3fr) minmax(260px, 1.2fr);
}

.attention-calibration-panel__running-top .attention-calibration-panel__stats-grid {
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.attention-calibration-panel__stat-card {
  background: rgba(8, 10, 22, 0.74);
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 12px;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.03);
  padding: 12px 14px;
}

.attention-calibration-panel__stat-card--compact {
  height: 100%;
}

.attention-calibration-panel__stat-card--danger {
  background: rgba(88, 12, 26, 0.42);
  border-color: rgba(255, 102, 134, 0.34);
}

.attention-calibration-panel__stat-label {
  color: rgba(255, 255, 255, 0.78);
  font-size: 0.76rem;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.attention-calibration-panel__stat-value {
  color: rgba(248, 250, 252, 0.98);
  font-size: 1.6rem;
  font-weight: 700;
  line-height: 1.2;
  margin-top: 6px;
}

.attention-calibration-panel__target-block,
.attention-calibration-panel__intro-panel {
  background: rgba(8, 10, 22, 0.56);
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 14px;
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.02);
  padding: 14px 16px;
}

.attention-calibration-panel__target-block--inline {
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.attention-calibration-panel__eeg-chart-shell {
  background: rgba(8, 10, 22, 0.56);
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 14px;
  min-height: 170px;
  padding: 8px;
}

.attention-calibration-panel__eeg-chart {
  min-height: 154px;
}

.attention-calibration-panel__intro-block,
.attention-calibration-panel__summary-block {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.attention-calibration-panel__instruction-list {
  margin: 12px 0 0;
  padding-left: 20px;
}

.attention-calibration-panel__instruction-list li + li {
  margin-top: 8px;
}

.attention-calibration-panel__board {
  background:
    radial-gradient(circle at 12% 16%, rgba(255, 64, 96, 0.14), transparent 26%),
    radial-gradient(circle at 88% 18%, rgba(0, 255, 128, 0.14), transparent 24%),
    radial-gradient(circle at 50% 84%, rgba(72, 126, 255, 0.18), transparent 34%),
    linear-gradient(180deg, rgba(5, 7, 16, 0.96), rgba(3, 4, 12, 0.92));
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 18px;
  box-shadow:
    inset 0 0 0 1px rgba(255, 255, 255, 0.03),
    inset 0 0 28px rgba(255, 64, 96, 0.06),
    inset 0 0 36px rgba(0, 255, 128, 0.05),
    inset 0 0 44px rgba(72, 126, 255, 0.07);
  min-height: clamp(320px, 52vh, 560px);
  overflow: hidden;
  position: relative;
}

.attention-calibration-panel__token-button {
  --attention-token-stroke-rgb: 64, 255, 166;
  --attention-token-fill-rgb: 6, 28, 20;
  --attention-token-glow-rgb: 64, 255, 166;
  background: transparent;
  border: 0;
  cursor: pointer;
  left: 0;
  position: absolute;
  padding: 0;
  top: 0;
  transition:
    filter 140ms ease,
    transform 140ms ease;
}

.attention-calibration-panel__token-button:nth-child(3n + 1) {
  --attention-token-stroke-rgb: 64, 255, 166;
  --attention-token-fill-rgb: 5, 28, 18;
  --attention-token-glow-rgb: 64, 255, 166;
}

.attention-calibration-panel__token-button:nth-child(3n + 2) {
  --attention-token-stroke-rgb: 86, 156, 255;
  --attention-token-fill-rgb: 8, 16, 38;
  --attention-token-glow-rgb: 86, 156, 255;
}

.attention-calibration-panel__token-button:nth-child(3n + 3) {
  --attention-token-stroke-rgb: 255, 88, 118;
  --attention-token-fill-rgb: 40, 8, 18;
  --attention-token-glow-rgb: 255, 88, 118;
}

.attention-calibration-panel__token-button:hover {
  filter: brightness(1.18) saturate(1.2);
  transform: translateY(-2px);
}

.attention-calibration-panel__token-button:focus-visible {
  outline: 2px solid rgba(255, 255, 255, 0.92);
  outline-offset: 4px;
}

.attention-calibration-panel__token-button--wrong {
  animation: attention-calibration-wrong 180ms ease;
}

.attention-calibration-panel__token-svg {
  aspect-ratio: 1 / 1;
  display: block;
  height: 100%;
  width: 100%;
}

.attention-calibration-panel__token-shape {
  fill: rgba(var(--attention-token-fill-rgb), 0.9);
  stroke: rgba(var(--attention-token-stroke-rgb), 0.99);
  stroke-width: 4.5px;
}

.attention-calibration-panel__token-button--circle .attention-calibration-panel__token-svg,
.attention-calibration-panel__token-button--triangle .attention-calibration-panel__token-svg {
  filter:
    drop-shadow(0 0 16px rgba(var(--attention-token-glow-rgb), 0.4))
    drop-shadow(0 0 28px rgba(var(--attention-token-glow-rgb), 0.22));
}

.attention-calibration-panel__token-button--wrong .attention-calibration-panel__token-shape {
  fill: rgba(76, 12, 24, 0.86);
  stroke: rgba(255, 112, 144, 0.98);
}

.attention-calibration-panel__token-number {
  fill: rgba(255, 255, 255, 0.98);
  font-family: 'JetBrains Mono', 'Consolas', monospace;
  font-size: 1.18rem;
  font-weight: 700;
  letter-spacing: -0.05em;
  paint-order: stroke fill;
  stroke: rgba(5, 7, 16, 0.98);
  stroke-width: 3px;
  filter: drop-shadow(0 0 8px rgba(var(--attention-token-glow-rgb), 0.3));
}

.attention-calibration-panel__token-number--triangle {
  font-size: 1.08rem;
}

.attention-calibration-panel__token-number--compact {
  font-size: 0.98rem;
}

.attention-calibration-panel__footer {
  padding: 0 16px 16px;
}

@keyframes attention-calibration-wrong {
  0% {
    transform: translateX(0);
  }

  25% {
    transform: translateX(-4px);
  }

  50% {
    transform: translateX(4px);
  }

  100% {
    transform: translateX(0);
  }
}

@media (max-width: 768px) {
  .attention-calibration-panel__running-top {
    grid-template-columns: 1fr;
  }

  .attention-calibration-panel__running-top .attention-calibration-panel__stats-grid {
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  }

  .attention-calibration-panel__board {
    min-height: clamp(280px, 46vh, 420px);
  }

  .attention-calibration-panel__stat-value {
    font-size: 1.35rem;
  }
}
</style>