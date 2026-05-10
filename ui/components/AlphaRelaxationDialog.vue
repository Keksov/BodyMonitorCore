<template>
  <q-dialog
    :model-value="modelValue"
    persistent
    @update:model-value="onDialogModelUpdate"
  >
    <alpha-relaxation-game-panel
      v-if="modelValue"
      :previous-summary="previousSummary"
      :header-context="headerContext"
      show-close-button
      class="alpha-relaxation-dialog"
      @close="closeDialog"
      @clear="emit('clear')"
      @save="(summary) => emit('save', summary)"
    />
  </q-dialog>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AlphaRelaxationGamePanel from './AlphaRelaxationGamePanel.vue'
import type { AlphaRelaxationSummary } from '../stores/device'

const props = defineProps<{
  readonly modelValue: boolean
  readonly deviceMac: string | null
  readonly deviceName: string
  readonly previousSummary: AlphaRelaxationSummary | null
}>()

const emit = defineEmits<{
  (event: 'update:modelValue', value: boolean): void
  (event: 'clear'): void
  (event: 'save', value: AlphaRelaxationSummary): void
}>()

const { t } = useI18n()
const headerContext = computed(() => {
  const deviceName = props.deviceName.trim() !== '' ? props.deviceName : t('capability.device')
  const deviceMac = props.deviceMac ?? '—'
  return t('calibration.deviceLabel', { name: deviceName, mac: deviceMac })
})

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
.alpha-relaxation-dialog {
  max-width: min(960px, 96vw);
  width: min(960px, 96vw);
}

@media (max-width: 768px) {
  .alpha-relaxation-dialog {
    width: min(96vw, 96vw);
  }
}
</style>