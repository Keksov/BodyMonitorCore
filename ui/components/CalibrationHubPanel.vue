<template>
  <div class="calibration-hub">
    <div v-if="activeMode === null" class="calibration-hub__layout">
      <div class="calibration-hub__hero row items-start justify-between q-col-gutter-md">
        <div class="col">
          <div class="text-h5">{{ t('calibration.hub.title') }}</div>
          <div class="text-body2 text-grey-5 q-mt-sm">{{ t('calibration.hub.subtitle') }}</div>
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
      </div>

      <div class="calibration-hub__selector-grid">
        <div class="calibration-hub__guide">
          <div class="text-subtitle1">{{ t('calibration.hub.guideTitle') }}</div>
          <div class="text-body2 text-grey-5 q-mt-sm">{{ t('calibration.hub.guideIntro') }}</div>

          <ul class="calibration-hub__guide-list text-body2 text-grey-4">
            <li>{{ t('calibration.hub.guideStabilization') }}</li>
            <li>{{ t('calibration.hub.guideFit') }}</li>
            <li>{{ t('calibration.hub.guideModes') }}</li>
            <li>{{ t('calibration.hub.guideRecommendation') }}</li>
          </ul>

          <div :class="profileStatusClassNames">
            {{ profileStatusText }}
          </div>
        </div>

        <div :class="selectorStackClassName('attention')">
          <button
            type="button"
            :class="selectorClassName('attention')"
            @click="openMode('attention')"
          >
            <span class="calibration-hub__selector-title">{{ t('calibration.hub.attentionButton') }}</span>
            <span class="calibration-hub__selector-caption">{{ t('calibration.hub.attentionCaption') }}</span>
            <span class="calibration-hub__selector-note">{{ t('calibration.hub.attentionHint') }}</span>
          </button>
        </div>

        <div :class="selectorStackClassName('relaxation')">
          <button
            type="button"
            :class="selectorClassName('relaxation')"
            @click="openMode('relaxation')"
          >
            <span class="calibration-hub__selector-title">{{ t('calibration.hub.relaxationButton') }}</span>
            <span class="calibration-hub__selector-caption">{{ t('calibration.hub.relaxationCaption') }}</span>
            <span class="calibration-hub__selector-note">{{ t('calibration.hub.relaxationHint') }}</span>
          </button>
        </div>

        <div :class="selectorStackClassName('drowse')">
          <button
            type="button"
            :class="selectorClassName('drowse')"
            @click="openMode('drowse')"
          >
            <span class="calibration-hub__selector-title">{{ t('calibration.hub.drowseButton') }}</span>
            <span class="calibration-hub__selector-caption">{{ t('calibration.hub.drowseCaption') }}</span>
            <span class="calibration-hub__selector-note">{{ t('calibration.hub.drowseHint') }}</span>
          </button>
        </div>
      </div>
    </div>

    <div v-else class="calibration-hub__active-panel">
      <attention-calibration-game-panel
        v-if="activeMode === 'attention'"
        :previous-summary="previousAttentionSummary"
        :device-mac="deviceMac"
        :show-close-button="true"
        @close="closeMode"
        @clear="emit('attention-clear')"
        @save="(summary) => emit('attention-save', summary)"
      />

      <alpha-relaxation-game-panel
        v-else-if="activeMode === 'relaxation'"
        :previous-summary="previousAlphaRelaxationSummary"
        :device-mac="deviceMac"
        :show-close-button="true"
        @close="closeMode"
        @clear="emit('alpha-relaxation-clear')"
        @save="(summary) => emit('alpha-relaxation-save', summary)"
      />

      <sleep-drowse-game-panel
        v-else
        :previous-summary="previousDrowseSummary"
        :device-mac="deviceMac"
        :show-close-button="true"
        @close="closeMode"
        @clear="emit('drowse-clear')"
        @save="(summary) => emit('drowse-save', summary)"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import AlphaRelaxationGamePanel from './AlphaRelaxationGamePanel.vue'
import AttentionCalibrationGamePanel from './AttentionCalibrationGamePanel.vue'
import SleepDrowseGamePanel from './SleepDrowseGamePanel.vue'
import {
  useDeviceStore,
  type AlphaRelaxationSummary,
  type AttentionCalibrationSummary,
  type DrowseCalibrationSummary,
} from '../stores/device'

type CalibrationMode = 'attention' | 'relaxation' | 'drowse'
type CalibrationModeVisualState = 'complete' | 'pending'
type CalibrationModeStates = Record<CalibrationMode, CalibrationModeVisualState>

const props = withDefaults(defineProps<{
  readonly previousAttentionSummary: AttentionCalibrationSummary | null
  readonly previousAlphaRelaxationSummary: AlphaRelaxationSummary | null
  readonly previousDrowseSummary?: DrowseCalibrationSummary | null
  readonly deviceMac?: string | null
  readonly initialMode?: CalibrationMode | null
  readonly modeStates?: CalibrationModeStates
  readonly showCloseButton?: boolean
}>(), {
  previousDrowseSummary: null,
  deviceMac: null,
  initialMode: null,
  modeStates: () => ({
    attention: 'pending',
    relaxation: 'pending',
    drowse: 'pending',
  }),
  showCloseButton: false,
})

const emit = defineEmits<{
  (event: 'close'): void
  (event: 'attention-clear'): void
  (event: 'alpha-relaxation-clear'): void
  (event: 'drowse-clear'): void
  (event: 'attention-save', value: AttentionCalibrationSummary): void
  (event: 'alpha-relaxation-save', value: AlphaRelaxationSummary): void
  (event: 'drowse-save', value: DrowseCalibrationSummary): void
}>()

const device = useDeviceStore()
const { t } = useI18n()
const selectedMode = ref<CalibrationMode>(props.initialMode ?? 'attention')
const activeMode = ref<CalibrationMode | null>(props.initialMode)

const activeProfile = computed(() => {
  if (props.deviceMac === null) {
    return null
  }

  return device.getEegCalibrationProfile(props.deviceMac)
})

const missingModes = computed(() => {
  const completedModes = activeProfile.value?.completedModes
  if (completedModes === undefined) {
    return ['attention', 'relaxation', 'drowse'] as CalibrationMode[]
  }

  const result: CalibrationMode[] = []
  if (!completedModes.attention) {
    result.push('attention')
  }
  if (!completedModes.alphaRelaxation) {
    result.push('relaxation')
  }
  if (!completedModes.drowse) {
    result.push('drowse')
  }

  return result
})

const missingModesLabel = computed(() => {
  return missingModes.value.map((mode) => t(`calibration.hub.${mode}Button`)).join(', ')
})

const profileStatusText = computed(() => {
  if (props.deviceMac === null) {
    return t('calibration.hub.profileUnknown')
  }

  if (activeProfile.value === null) {
    return t('calibration.hub.profileMissing')
  }

  if (activeProfile.value.isComplete) {
    return t('calibration.hub.profileReady')
  }

  return t('calibration.hub.profileIncomplete', { modes: missingModesLabel.value })
})

const profileStatusClassNames = computed(() => {
  const classNames = ['calibration-hub__guide-status']
  if (props.deviceMac === null) {
    classNames.push('calibration-hub__guide-status--unknown')
    return classNames
  }

  if (activeProfile.value?.isComplete) {
    classNames.push('calibration-hub__guide-status--ready')
    return classNames
  }

  classNames.push('calibration-hub__guide-status--incomplete')
  return classNames
})

watch(() => props.initialMode, (value) => {
  if (value !== null) {
    selectedMode.value = value
  }
  activeMode.value = value
})

function selectorClassName(mode: CalibrationMode): string[] {
  return [
    'calibration-hub__selector',
    `calibration-hub__selector--${mode}`,
    `calibration-hub__selector--${props.modeStates[mode]}`,
    ...(selectedMode.value === mode ? ['calibration-hub__selector--active'] : []),
  ]
}

function selectorStackClassName(mode: CalibrationMode): string[] {
  return [
    'calibration-hub__selector-stack',
    ...(selectedMode.value === mode ? ['calibration-hub__selector-stack--active'] : []),
  ]
}

function openMode(mode: CalibrationMode): void {
  selectedMode.value = mode
  activeMode.value = mode
}

function closeMode(): void {
  activeMode.value = null
}
</script>

<style scoped>
.calibration-hub {
  box-sizing: border-box;
  padding: 20px;
  width: 100%;
}

.calibration-hub__layout {
  display: grid;
  gap: 20px;
  width: 100%;
}

.calibration-hub__hero {
  margin: 0;
}

.calibration-hub__selector-grid {
  align-items: start;
  display: grid;
  gap: 16px;
  grid-template-columns: repeat(12, minmax(0, 1fr));
}

.calibration-hub__guide {
  background: rgba(15, 23, 42, 0.62);
  border: 1px solid rgba(148, 163, 184, 0.24);
  border-radius: 18px;
  display: grid;
  gap: 10px;
  grid-column: span 12;
  padding: 18px;
}

.calibration-hub__guide-list {
  margin: 0;
  padding-left: 18px;
}

.calibration-hub__guide-list li + li {
  margin-top: 6px;
}

.calibration-hub__guide-status {
  border-radius: 12px;
  font-size: 0.9rem;
  font-weight: 600;
  padding: 9px 10px;
}

.calibration-hub__guide-status--unknown {
  background: rgba(71, 85, 105, 0.2);
  border: 1px solid rgba(148, 163, 184, 0.28);
  color: #cbd5e1;
}

.calibration-hub__guide-status--ready {
  background: rgba(6, 95, 70, 0.24);
  border: 1px solid rgba(16, 185, 129, 0.46);
  color: #a7f3d0;
}

.calibration-hub__guide-status--incomplete {
  background: rgba(146, 64, 14, 0.24);
  border: 1px solid rgba(251, 146, 60, 0.4);
  color: #fed7aa;
}

.calibration-hub__selector-stack {
  display: grid;
  gap: 16px;
  grid-column: span 4;
}

.calibration-hub__active-panel {
  min-width: 0;
  width: 100%;
}

.calibration-hub__selector {
  align-items: start;
  background:
    radial-gradient(circle at top right, rgba(255, 255, 255, 0.08), transparent 34%),
    rgba(15, 23, 42, 0.88);
  border: 1px solid rgba(148, 163, 184, 0.22);
  border-radius: 20px;
  color: #f8fafc;
  cursor: pointer;
  display: grid;
  gap: 12px;
  min-height: 180px;
  padding: 22px;
  text-align: left;
  transition: transform 140ms ease, border-color 140ms ease, box-shadow 140ms ease;
}

.calibration-hub__selector:hover {
  transform: translateY(-2px);
}

.calibration-hub__selector--complete {
  border-color: rgba(34, 197, 94, 0.52);
  box-shadow: inset 0 0 0 1px rgba(74, 222, 128, 0.12);
}

.calibration-hub__selector--pending {
  border-color: rgba(245, 158, 11, 0.46);
  box-shadow: inset 0 0 0 1px rgba(251, 191, 36, 0.1);
}

.calibration-hub__selector--active {
  transform: translateY(-2px);
}

.calibration-hub__selector--complete.calibration-hub__selector--active {
  box-shadow: inset 0 0 0 1px rgba(74, 222, 128, 0.12), 0 18px 36px rgba(22, 163, 74, 0.18);
}

.calibration-hub__selector--pending.calibration-hub__selector--active {
  box-shadow: inset 0 0 0 1px rgba(251, 191, 36, 0.1), 0 18px 36px rgba(217, 119, 6, 0.18);
}

.calibration-hub__selector-title {
  font-size: clamp(1.35rem, 3vw, 1.9rem);
  font-weight: 700;
  letter-spacing: 0.04em;
}

.calibration-hub__selector-caption {
  color: #cbd5e1;
  font-size: 0.95rem;
  line-height: 1.45;
}

.calibration-hub__selector-note {
  background: rgba(2, 6, 23, 0.42);
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 14px;
  color: #f8fafc;
  display: inline-flex;
  font-size: 0.95rem;
  font-weight: 600;
  padding: 10px 12px;
}

.calibration-hub :deep(.attention-calibration-panel),
.calibration-hub :deep(.alpha-relaxation-panel),
.calibration-hub :deep(.sleep-drowse-panel) {
  width: 100%;
}

.calibration-hub__active-panel :deep(.attention-calibration-panel__board) {
  min-height: clamp(420px, 62vh, 760px);
}

.calibration-hub :deep(.attention-calibration-panel__body),
.calibration-hub :deep(.alpha-relaxation-panel__body),
.calibration-hub :deep(.sleep-drowse-panel__body) {
  padding-top: 2px;
}

@media (max-width: 900px) {
  .calibration-hub__selector-grid {
    grid-template-columns: 1fr;
  }

  .calibration-hub__selector-stack {
    grid-column: auto;
  }

  .calibration-hub__active-panel :deep(.attention-calibration-panel__board) {
    min-height: clamp(320px, 52vh, 520px);
  }
}
</style>