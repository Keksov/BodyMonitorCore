<template>
  <q-dialog
    :model-value="modelValue"
    persistent
    @update:model-value="onDialogModelUpdate"
  >
    <calibration-hub-panel
      v-if="modelValue"
      :previous-attention-summary="previousAttentionSummary"
      :previous-alpha-relaxation-summary="previousAlphaRelaxationSummary"
      :previous-drowse-summary="previousDrowseSummary"
      :device-mac="deviceMac"
      :initial-mode="initialMode"
      :mode-states="modeStates"
      :show-close-button="true"
      class="calibration-hub-dialog"
      @close="closeDialog"
      @attention-clear="emit('attention-clear')"
      @alpha-relaxation-clear="emit('alpha-relaxation-clear')"
      @drowse-clear="emit('drowse-clear')"
      @attention-save="(summary) => emit('attention-save', summary)"
      @alpha-relaxation-save="(summary) => emit('alpha-relaxation-save', summary)"
      @drowse-save="(summary) => emit('drowse-save', summary)"
    />
  </q-dialog>
</template>

<script setup lang="ts">
import CalibrationHubPanel from './CalibrationHubPanel.vue'
import type {
  AlphaRelaxationSummary,
  AttentionCalibrationSummary,
  DrowseCalibrationSummary,
} from '../stores/device'

type CalibrationMode = 'attention' | 'relaxation' | 'drowse'
type CalibrationModeVisualState = 'complete' | 'pending'
type CalibrationModeStates = Record<CalibrationMode, CalibrationModeVisualState>

const props = withDefaults(defineProps<{
  readonly modelValue: boolean
  readonly previousAttentionSummary: AttentionCalibrationSummary | null
  readonly previousAlphaRelaxationSummary: AlphaRelaxationSummary | null
  readonly previousDrowseSummary?: DrowseCalibrationSummary | null
  readonly deviceMac?: string | null
  readonly initialMode?: 'attention' | 'relaxation' | 'drowse' | null
  readonly modeStates?: CalibrationModeStates
}>(), {
  previousDrowseSummary: null,
  deviceMac: null,
  initialMode: null,
  modeStates: () => ({
    attention: 'pending',
    relaxation: 'pending',
    drowse: 'pending',
  }),
})

const emit = defineEmits<{
  (event: 'update:modelValue', value: boolean): void
  (event: 'attention-clear'): void
  (event: 'alpha-relaxation-clear'): void
  (event: 'drowse-clear'): void
  (event: 'attention-save', value: AttentionCalibrationSummary): void
  (event: 'alpha-relaxation-save', value: AlphaRelaxationSummary): void
  (event: 'drowse-save', value: DrowseCalibrationSummary): void
}>()

function onDialogModelUpdate(value: boolean): void {
  if (!value) {
    closeDialog()
  }
}

function closeDialog(): void {
  emit('update:modelValue', false)
}
</script>

<style scoped>
.calibration-hub-dialog {
  background: rgba(2, 6, 23, 0.98);
  border: 1px solid rgba(148, 163, 184, 0.22);
  border-radius: 24px;
  box-shadow: 0 24px 64px rgba(2, 6, 23, 0.62);
  max-width: min(1120px, 96vw);
  overflow: hidden;
  width: min(1120px, 96vw);
}

@media (max-width: 768px) {
  .calibration-hub-dialog {
    width: 96vw;
  }
}
</style>