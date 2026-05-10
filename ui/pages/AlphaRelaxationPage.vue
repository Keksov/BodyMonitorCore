<template>
  <q-page padding class="alpha-relaxation-page">
    <div class="alpha-relaxation-page__content">
      <alpha-relaxation-game-panel
        :previous-summary="lastSummary"
        :header-context="t('calibration.debugContext')"
        @save="onSummarySaved"
      />
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import AlphaRelaxationGamePanel from '../components/AlphaRelaxationGamePanel.vue'
import type { AlphaRelaxationSummary } from '../stores/device'

const { t } = useI18n()
const lastSummary = ref<AlphaRelaxationSummary | null>(null)

function onSummarySaved(summary: AlphaRelaxationSummary): void {
  lastSummary.value = summary
}
</script>

<style scoped>
.alpha-relaxation-page {
  display: flex;
  min-height: 100%;
}

.alpha-relaxation-page__content {
  display: flex;
  flex: 1 1 auto;
  min-width: 0;
}

.alpha-relaxation-page__content :deep(.alpha-relaxation-panel) {
  width: 100%;
}
</style>