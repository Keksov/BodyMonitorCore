<template>
  <div class="eeg-chart-side-panel">
    <div class="eeg-chart-side-panel__canvas-wrap">
      <slot />

      <div class="eeg-chart-side-panel__overlay-open-control">
        <q-btn
          v-if="props.showOpenButton && isPanelEnabled && !isPanelVisible"
          class="eeg-chart-side-panel__open-button"
          dense
          round
          size="xs"
          color="primary"
          text-color="white"
          icon="settings"
          :aria-label="openButtonLabel"
          :title="openButtonLabel"
          @click="openPanel"
        />
      </div>

      <div class="eeg-chart-side-panel__overlay-indicators">
        <slot name="overlay" />
      </div>

      <transition name="eeg-chart-side-panel-backdrop">
        <div
          v-if="isPanelEnabled && isPanelVisible"
          class="eeg-chart-side-panel__backdrop"
          aria-hidden="true"
          @click="closePanel"
        />
      </transition>

      <transition name="eeg-chart-side-panel-panel">
        <aside
          v-if="isPanelEnabled && isPanelVisible"
          class="eeg-chart-side-panel__panel"
          role="complementary"
          :aria-label="panelAriaLabelText"
        >
          <div class="eeg-chart-side-panel__panel-header">
            <div class="eeg-chart-side-panel__panel-title-row">
              <div class="eeg-chart-side-panel__panel-title">{{ panelTitle }}</div>
              <q-btn
                dense
                flat
                round
                size="sm"
                icon="close"
                color="primary"
                :aria-label="closeButtonLabel"
                :title="closeButtonLabel"
                @click="closePanel"
              />
            </div>

            <div v-if="showPanelSubtitle" class="eeg-chart-side-panel__panel-subtitle">
              {{ panelSubtitle }}
            </div>
          </div>

          <div v-if="hasPanelActions" class="eeg-chart-side-panel__panel-actions">
            <slot name="panelActions" />
          </div>

          <div class="eeg-chart-side-panel__panel-body">
            <slot name="panelBody" />
          </div>
        </aside>
      </transition>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch, useSlots } from 'vue'

const props = withDefaults(defineProps<{
  readonly uiStateScope?: string | null
  readonly storageKey?: string
  readonly panelTitle: string
  readonly panelSubtitle?: string | null
  readonly panelAriaLabel?: string | null
  readonly openButtonLabel: string
  readonly closeButtonLabel: string
  readonly showByDefault?: boolean
  readonly showOpenButton?: boolean
}>(), {
  uiStateScope: null,
  storageKey: 'eeg-side-panel-visible',
  panelSubtitle: null,
  panelAriaLabel: null,
  showByDefault: true,
  showOpenButton: true,
})

const slots = useSlots()
const isPanelVisible = ref<boolean>(props.showByDefault)

function buildStorageKey(scope: string, key: string): string {
  return `mindwave-eeg-${scope}-${key}`
}

function loadStoredPanelVisible(scope: string, key: string): boolean | null {
  try {
    const raw = localStorage.getItem(buildStorageKey(scope, key))
    if (raw === null) {
      return null
    }

    const parsed = JSON.parse(raw) as unknown
    return typeof parsed === 'boolean' ? parsed : null
  } catch {
    return null
  }
}

function saveStoredPanelVisible(scope: string, key: string, isVisible: boolean): void {
  try {
    localStorage.setItem(buildStorageKey(scope, key), JSON.stringify(isVisible))
  } catch {
    // Ignore localStorage failures.
  }
}

const normalizedScope = computed<string | null>(() => {
  const trimmed = props.uiStateScope?.trim()
  return trimmed !== undefined && trimmed !== '' ? trimmed : null
})

const isPanelEnabled = computed(() => normalizedScope.value !== null)

const showPanelSubtitle = computed(() => {
  return props.panelSubtitle !== null && props.panelSubtitle !== ''
})

const panelAriaLabelText = computed(() => {
  if (props.panelAriaLabel !== null && props.panelAriaLabel !== '') {
    return props.panelAriaLabel
  }

  return props.panelTitle
})

const hasPanelActions = computed(() => slots.panelActions !== undefined)

function openPanel(): void {
  if (!isPanelEnabled.value) {
    return
  }

  isPanelVisible.value = true
}

function closePanel(): void {
  if (!isPanelEnabled.value) {
    return
  }

  isPanelVisible.value = false
}

watch([normalizedScope, () => props.storageKey, () => props.showByDefault], ([scope, key, showByDefault]) => {
  if (scope === null) {
    isPanelVisible.value = false
    return
  }

  isPanelVisible.value = loadStoredPanelVisible(scope, key) ?? showByDefault
}, { immediate: true })

watch([normalizedScope, () => props.storageKey, isPanelVisible], ([scope, key, isVisible]) => {
  if (scope === null) {
    return
  }

  saveStoredPanelVisible(scope, key, isVisible)
})

function isPanelCurrentlyVisible(): boolean {
  return isPanelVisible.value
}

defineExpose({
  openPanel,
  closePanel,
  isPanelVisible: isPanelCurrentlyVisible,
})
</script>

<style scoped>
.eeg-chart-side-panel {
  display: flex;
  flex: 1 1 auto;
  min-height: 0;
  min-width: 0;
  overflow: hidden;
  width: 100%;
}

.eeg-chart-side-panel__canvas-wrap {
  display: flex;
  position: relative;
  flex: 1 1 auto;
  min-height: 0;
  min-width: 0;
  overflow: hidden;
}

.eeg-chart-side-panel__overlay-open-control {
  align-items: flex-end;
  bottom: 6px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  position: absolute;
  right: 4px;
  z-index: 10;
}

.eeg-chart-side-panel__overlay-indicators {
  align-items: flex-end;
  display: flex;
  flex-direction: column;
  gap: 6px;
  position: absolute;
  right: 12px;
  top: 8px;
  z-index: 10;
}

.eeg-chart-side-panel__open-button {
  border: 1px solid rgba(37, 99, 235, 0.2);
  min-height: 34px;
  min-width: 34px;
  pointer-events: auto;
}

.eeg-chart-side-panel__backdrop {
  background: rgba(15, 23, 42, 0.16);
  inset: 0;
  position: absolute;
  z-index: 20;
}

.eeg-chart-side-panel__panel {
  background: linear-gradient(180deg, #ffffff 0%, #f8fafc 100%);
  border: 1px solid rgba(148, 163, 184, 0.24);
  border-radius: 0;
  box-shadow: 0 18px 40px rgba(15, 23, 42, 0.18);
  bottom: 0;
  display: flex;
  flex-direction: column;
  max-width: calc(100% - 56px);
  overflow: hidden;
  position: absolute;
  right: 0;
  top: 0;
  width: 290px;
  z-index: 30;
}

.eeg-chart-side-panel-backdrop-enter-active,
.eeg-chart-side-panel-backdrop-leave-active {
  transition: opacity 0.18s ease;
}

.eeg-chart-side-panel-backdrop-enter-from,
.eeg-chart-side-panel-backdrop-leave-to {
  opacity: 0;
}

.eeg-chart-side-panel-panel-enter-active,
.eeg-chart-side-panel-panel-leave-active {
  transition: opacity 0.22s ease, transform 0.22s ease;
}

.eeg-chart-side-panel-panel-enter-from,
.eeg-chart-side-panel-panel-leave-to {
  opacity: 0;
  transform: translateX(24px);
}

.eeg-chart-side-panel__panel-header {
  border-bottom: 1px solid rgba(148, 163, 184, 0.2);
  padding: 10px 12px;
}

.eeg-chart-side-panel__panel-title-row {
  align-items: center;
  display: flex;
  gap: 8px;
  justify-content: space-between;
}

.eeg-chart-side-panel__panel-title {
  color: #0f172a;
  font-size: 14px;
  font-weight: 700;
  line-height: 1.2;
}

.eeg-chart-side-panel__panel-subtitle {
  color: #64748b;
  font-size: 12px;
  line-height: 1.2;
  margin-top: 3px;
}

.eeg-chart-side-panel__panel-actions {
  border-bottom: 1px solid rgba(148, 163, 184, 0.16);
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  justify-content: flex-start;
  padding: 8px 10px;
}

.eeg-chart-side-panel__panel-body {
  display: flex;
  flex: 1 1 auto;
  flex-direction: column;
  min-height: 0;
  overflow: auto;
  padding: 8px;
}

@media (max-width: 1100px) {
  .eeg-chart-side-panel__panel {
    width: 250px;
  }
}

@media (max-width: 899px) {
  .eeg-chart-side-panel__panel {
    max-width: none;
    width: 100%;
  }
}
</style>
