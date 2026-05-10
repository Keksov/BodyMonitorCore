<template>
  <q-page padding class="calibration-page">
    <div class="calibration-page__content">
      <calibration-hub-panel
        :previous-attention-summary="lastAttentionSummary"
        :previous-alpha-relaxation-summary="lastAlphaRelaxationSummary"
        @attention-clear="onAttentionSummaryCleared"
        @alpha-relaxation-clear="onAlphaRelaxationSummaryCleared"
        @attention-save="onAttentionSummarySaved"
        @alpha-relaxation-save="onAlphaRelaxationSummarySaved"
      />
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import CalibrationHubPanel from '../components/CalibrationHubPanel.vue'
import type { AlphaRelaxationSummary, AttentionCalibrationSummary } from '../stores/device'

const lastAttentionSummary = ref<AttentionCalibrationSummary | null>(null)
const lastAlphaRelaxationSummary = ref<AlphaRelaxationSummary | null>(null)

function onAttentionSummarySaved(summary: AttentionCalibrationSummary): void {
  lastAttentionSummary.value = summary
}

function onAttentionSummaryCleared(): void {
  lastAttentionSummary.value = null
}

function onAlphaRelaxationSummarySaved(summary: AlphaRelaxationSummary): void {
  lastAlphaRelaxationSummary.value = summary
}

function onAlphaRelaxationSummaryCleared(): void {
  lastAlphaRelaxationSummary.value = null
}
</script>

<style scoped>
.calibration-page {
  display: flex;
  min-height: 100%;
}

.calibration-page__content {
  display: flex;
  flex: 1 1 auto;
  min-width: 0;
  width: 100%;
}

.calibration-page__content :deep(.calibration-hub) {
  width: 100%;
}
</style>