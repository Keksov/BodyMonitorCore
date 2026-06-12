<template>
  <div class="eeg-signal-style-editor">
    <div class="eeg-signal-style-editor__header">
      <div class="eeg-signal-style-editor__title">{{ t('monitoring.eegStyle.editorTitle') }}</div>
      <div class="eeg-signal-style-editor__subtitle">{{ signalLabel }}</div>
    </div>

    <div class="eeg-signal-style-editor__section">
      <div class="eeg-signal-style-editor__label">{{ t('monitoring.eegStyle.colorLabel') }}</div>
      <div class="eeg-signal-style-editor__color-row">
        <input
          class="eeg-signal-style-editor__color-picker"
          type="color"
          :value="colorModel"
          @input="handleColorInput"
        >
        <span class="eeg-signal-style-editor__color-code">{{ colorModel.toUpperCase() }}</span>
      </div>
    </div>

    <template v-if="allowLineOptions">
      <div class="eeg-signal-style-editor__section">
        <q-select
          dense
          outlined
          emit-value
          map-options
          :label="t('monitoring.eegStyle.lineTypeLabel')"
          :model-value="lineTypeModel"
          :options="lineTypeOptions"
          @update:model-value="handleLineTypeChange"
        />
      </div>

      <div class="eeg-signal-style-editor__section">
        <div class="eeg-signal-style-editor__label-row">
          <span class="eeg-signal-style-editor__label">{{ t('monitoring.eegStyle.glowLabel') }}</span>
          <span class="eeg-signal-style-editor__value">{{ glowLabel }}</span>
        </div>
        <q-slider
          :model-value="glowModel"
          :min="0"
          :max="36"
          :step="1"
          color="primary"
          track-color="grey-4"
          thumb-color="primary"
          @update:model-value="handleGlowChange"
        />
      </div>
    </template>

    <div class="eeg-signal-style-editor__section">
      <div class="eeg-signal-style-editor__label">{{ t('monitoring.eegStyle.previewLabel') }}</div>
      <div class="eeg-signal-style-editor__preview-surface">
        <span class="eeg-signal-style-editor__preview-line" :style="previewLineStyle" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useEegSignalStyleStore, type EegSignalLineType } from '../stores/eeg-signal-style'

const props = withDefaults(defineProps<{
  readonly signalKey: string
  readonly signalLabel: string
  readonly allowLineOptions?: boolean
}>(), {
  allowLineOptions: false,
})

const { t } = useI18n()
const signalStyleStore = useEegSignalStyleStore()

const lineTypeOptions = computed(() => ([
  { label: t('monitoring.eegStyle.lineType.solid'), value: 'solid' },
  { label: t('monitoring.eegStyle.lineType.dashed'), value: 'dashed' },
  { label: t('monitoring.eegStyle.lineType.dotted'), value: 'dotted' },
  { label: t('monitoring.eegStyle.lineType.twodash'), value: 'twodash' },
  { label: t('monitoring.eegStyle.lineType.longdash'), value: 'longdash' },
  { label: t('monitoring.eegStyle.lineType.dotdash'), value: 'dotdash' },
]))

const activeSignalStyle = computed(() => {
  return signalStyleStore.getSignalStyle(props.signalKey)
})

const colorModel = computed(() => activeSignalStyle.value.color)
const lineTypeModel = computed(() => activeSignalStyle.value.lineType)
const glowModel = computed(() => activeSignalStyle.value.glowIntensity)

const glowLabel = computed(() => {
  if (glowModel.value <= 0) {
    return t('monitoring.eegStyle.glowOff')
  }

  return t('monitoring.eegStyle.glowValue', { value: glowModel.value })
})

const previewLineStyle = computed<Record<string, string>>(() => {
  const style = activeSignalStyle.value
  const previewPattern = resolvePreviewLinePattern(style.lineType, style.color)

  return {
    ...previewPattern,
    boxShadow: style.glowIntensity > 0
      ? `0 0 ${style.glowIntensity}px ${style.color}`
      : 'none',
  }
})

function resolvePreviewLinePattern(lineType: EegSignalLineType, color: string): Record<string, string> {
  switch (lineType) {
    case 'solid':
      return {
        background: color,
      }
    case 'dashed':
      return {
        background: `repeating-linear-gradient(to right, ${color} 0 12px, transparent 12px 20px)`,
      }
    case 'dotted':
      return {
        background: `repeating-linear-gradient(to right, ${color} 0 2px, transparent 2px 8px)`,
      }
    case 'twodash':
      return {
        background: `repeating-linear-gradient(to right, ${color} 0 8px, transparent 8px 13px, ${color} 13px 21px, transparent 21px 34px)`,
      }
    case 'longdash':
      return {
        background: `repeating-linear-gradient(to right, ${color} 0 22px, transparent 22px 30px)`,
      }
    case 'dotdash':
      return {
        background: `repeating-linear-gradient(to right, ${color} 0 2px, transparent 2px 8px, ${color} 8px 22px, transparent 22px 30px)`,
      }
    default:
      return {
        background: color,
      }
  }
}

function handleColorInput(event: Event): void {
  const target = event.target as HTMLInputElement | null
  if (target === null) {
    return
  }

  signalStyleStore.setSignalColor(props.signalKey, target.value)
}

function handleLineTypeChange(value: unknown): void {
  if (
    value !== 'solid'
    && value !== 'dashed'
    && value !== 'dotted'
    && value !== 'twodash'
    && value !== 'longdash'
    && value !== 'dotdash'
  ) {
    return
  }

  signalStyleStore.setSignalLineType(props.signalKey, value as EegSignalLineType)
}

function handleGlowChange(value: number | null): void {
  if (value === null || !Number.isFinite(value)) {
    return
  }

  signalStyleStore.setSignalGlowIntensity(props.signalKey, value)
}
</script>

<style scoped>
.eeg-signal-style-editor {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.eeg-signal-style-editor__header {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.eeg-signal-style-editor__title {
  color: #0b1220;
  font-size: 14px;
  font-weight: 700;
  line-height: 1.2;
}

.eeg-signal-style-editor__subtitle {
  color: #1f2937;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.2;
}

.eeg-signal-style-editor__section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.eeg-signal-style-editor__label-row {
  align-items: center;
  display: flex;
  justify-content: space-between;
}

.eeg-signal-style-editor__label {
  color: #0f172a;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.2;
}

.eeg-signal-style-editor__value {
  color: #1e293b;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.2;
}

.eeg-signal-style-editor__color-row {
  align-items: center;
  display: flex;
  gap: 10px;
}

.eeg-signal-style-editor__color-picker {
  appearance: none;
  background: transparent;
  border: 1px solid rgba(148, 163, 184, 0.35);
  border-radius: 8px;
  cursor: pointer;
  flex: 0 0 auto;
  height: 32px;
  padding: 2px;
  width: 48px;
}

.eeg-signal-style-editor__color-code {
  color: #0f172a;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.03em;
}

.eeg-signal-style-editor__preview-surface {
  align-items: center;
  background: rgba(148, 163, 184, 0.12);
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: 8px;
  display: flex;
  height: 44px;
  padding: 0 10px;
}

.eeg-signal-style-editor__preview-line {
  border-radius: 2px;
  display: block;
  height: 3px;
  width: 100%;
}

:deep(.q-field__label) {
  color: #0f172a !important;
  font-weight: 700;
}

:deep(.q-field__native),
:deep(.q-field__input),
:deep(.q-field__marginal) {
  color: #0f172a;
}
</style>
