<template>
  <div ref="panelRootRef" class="eeg-signal-style-list-panel">
    <div v-if="showVisibilityActions" class="eeg-signal-style-list-panel__actions">
      <q-btn
        flat
        dense
        no-caps
        color="primary"
        icon="visibility"
        :label="t('monitoring.eegLine.showAll')"
        @click="emit('set-all-visible', true)"
      />
      <q-btn
        flat
        dense
        no-caps
        color="primary"
        icon="visibility_off"
        :label="t('monitoring.eegLine.hideAll')"
        @click="emit('set-all-visible', false)"
      />
    </div>

    <div class="eeg-signal-style-list-panel__list">
      <label
        v-for="entry in entries"
        :key="entry.key"
        class="eeg-signal-style-list-panel__item"
      >
        <q-checkbox
          v-if="entry.canToggleVisibility"
          dense
          color="primary"
          :model-value="entry.isVisible !== false"
          @update:model-value="emitVisibility(entry.key, $event)"
        />

        <div class="eeg-signal-style-list-panel__color-control">
          <button
            type="button"
            class="eeg-signal-style-list-panel__color-button"
            :title="t('monitoring.eegStyle.openEditor')"
            @click.stop.prevent="toggleStyleEditor(entry.key, $event)"
          >
            <span
              class="eeg-signal-style-list-panel__color-swatch"
              :style="{ backgroundColor: getSignalColor(entry.key) }"
            />
            <span
              class="eeg-signal-style-list-panel__line-preview"
              :style="getSignalLinePreviewStyle(entry.key)"
            />
          </button>
        </div>

        <span class="eeg-signal-style-list-panel__name">{{ entry.label }}</span>
      </label>
    </div>

    <span
      ref="styleAnchorRef"
      class="eeg-signal-style-list-panel__style-anchor"
      :style="{ left: `${styleAnchorLeftPx}px`, top: `${styleAnchorTopPx}px` }"
      aria-hidden="true"
    />

    <q-menu
      ref="editorMenuRef"
      :model-value="isEditorVisible"
      :target="styleAnchorRef"
      no-parent-event
      anchor="center left"
      self="center right"
      :offset="[0, 0]"
      transition-show="eeg-style-panel-slide"
      transition-hide="eeg-style-panel-slide"
      @update:model-value="handleEditorMenuToggle"
    >
      <q-card v-if="activeEntry !== null" class="eeg-signal-style-list-panel__editor-card">
        <q-card-section class="eeg-signal-style-list-panel__editor-header">
          <div class="eeg-signal-style-list-panel__editor-title">{{ t('monitoring.eegStyle.editorTitle') }}</div>
          <q-btn
            dense
            flat
            round
            icon="close"
            color="primary"
            :aria-label="t('common.closeAction')"
            :title="t('common.closeAction')"
            @click="closeStyleEditor"
          />
        </q-card-section>

        <q-separator />

        <q-card-section class="eeg-signal-style-list-panel__editor-body">
          <eeg-signal-style-editor
            :signal-key="activeEntry.key"
            :signal-label="activeEntry.label"
            :allow-line-options="activeEntry.allowLineOptions === true"
          />
        </q-card-section>
      </q-card>
    </q-menu>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import EegSignalStyleEditor from './EegSignalStyleEditor.vue'
import { useEegSignalStyleStore, type EegSignalLineType } from '../stores/eeg-signal-style'

interface EegSignalPanelEntry {
  readonly key: string
  readonly label: string
  readonly isVisible?: boolean
  readonly canToggleVisibility?: boolean
  readonly allowLineOptions?: boolean
}

const props = withDefaults(defineProps<{
  readonly entries: readonly EegSignalPanelEntry[]
  readonly showVisibilityActions?: boolean
}>(), {
  showVisibilityActions: false,
})

const emit = defineEmits<{
  'toggle-visibility': [payload: { key: string, isVisible: boolean }]
  'set-all-visible': [isVisible: boolean]
}>()

const { t } = useI18n()
const signalStyleStore = useEegSignalStyleStore()
const editedSignalKey = ref<string | null>(null)
const panelRootRef = ref<HTMLDivElement | null>(null)
const styleAnchorRef = ref<HTMLElement | null>(null)
const styleAnchorLeftPx = ref(-8)
const styleAnchorTopPx = ref(0)
const editorMenuRef = ref<{
  updatePosition?: () => void
} | null>(null)

const isEditorVisible = computed(() => editedSignalKey.value !== null)

const activeEntry = computed(() => {
  if (editedSignalKey.value === null) {
    return null
  }

  return props.entries.find((entry) => entry.key === editedSignalKey.value) ?? null
})

function getSignalColor(signalKey: string): string {
  return signalStyleStore.getSignalStyle(signalKey).color
}

function resolveLinePreviewBackground(lineType: EegSignalLineType, color: string): string {
  switch (lineType) {
    case 'solid':
      return color
    case 'dashed':
      return `repeating-linear-gradient(to right, ${color} 0 12px, transparent 12px 20px)`
    case 'dotted':
      return `repeating-linear-gradient(to right, ${color} 0 2px, transparent 2px 8px)`
    case 'twodash':
      return `repeating-linear-gradient(to right, ${color} 0 8px, transparent 8px 13px, ${color} 13px 21px, transparent 21px 34px)`
    case 'longdash':
      return `repeating-linear-gradient(to right, ${color} 0 22px, transparent 22px 30px)`
    case 'dotdash':
      return `repeating-linear-gradient(to right, ${color} 0 2px, transparent 2px 8px, ${color} 8px 22px, transparent 22px 30px)`
    default:
      return color
  }
}

function getSignalLinePreviewStyle(signalKey: string): Record<string, string> {
  const style = signalStyleStore.getSignalStyle(signalKey)

  return {
    background: resolveLinePreviewBackground(style.lineType, style.color),
    boxShadow: style.glowIntensity > 0
      ? `0 0 ${Math.max(2, Math.min(12, style.glowIntensity))}px ${style.color}`
      : 'none',
  }
}

function emitVisibility(signalKey: string, value: unknown): void {
  emit('toggle-visibility', {
    key: signalKey,
    isVisible: value !== false,
  })
}

function toggleStyleEditor(signalKey: string, event: MouseEvent): void {
  const target = event.currentTarget as HTMLElement | null
  if (target !== null) {
    updateAnchorTop(target)
  }

  editedSignalKey.value = editedSignalKey.value === signalKey ? null : signalKey

  nextTick(() => {
    editorMenuRef.value?.updatePosition?.()
  })
}

function updateAnchorTop(target: HTMLElement): void {
  const rootRect = panelRootRef.value?.getBoundingClientRect()
  const targetRect = target.getBoundingClientRect()
  if (rootRect === undefined) {
    return
  }

  const sidePanelElement = target.closest('.eeg-chart-side-panel__panel') as HTMLElement | null
  if (sidePanelElement !== null) {
    const sidePanelRect = sidePanelElement.getBoundingClientRect()
    styleAnchorLeftPx.value = Math.round(sidePanelRect.left - rootRect.left)
  }

  const centeredTop = targetRect.top - rootRect.top + (targetRect.height * 0.5)
  styleAnchorTopPx.value = Math.max(0, Math.round(centeredTop))
}

function handleEditorMenuToggle(isVisible: boolean): void {
  if (!isVisible) {
    closeStyleEditor()
  }
}

function closeStyleEditor(): void {
  editedSignalKey.value = null
}
</script>

<style scoped>
.eeg-signal-style-list-panel {
  display: flex;
  flex: 1 1 auto;
  flex-direction: column;
  gap: 8px;
  min-height: 0;
  position: relative;
}

.eeg-signal-style-list-panel__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  justify-content: flex-start;
}

.eeg-signal-style-list-panel__list {
  display: flex;
  flex: 1 1 auto;
  flex-direction: column;
  min-height: 0;
  overflow: auto;
}

.eeg-signal-style-list-panel__item {
  align-items: center;
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid rgba(148, 163, 184, 0.2);
  display: flex;
  gap: 8px;
  min-height: 38px;
  padding: 4px 8px;
}

.eeg-signal-style-list-panel__item + .eeg-signal-style-list-panel__item {
  margin-top: 6px;
}

.eeg-signal-style-list-panel__color-control {
  display: inline-flex;
  flex: 0 0 auto;
}

.eeg-signal-style-list-panel__style-anchor {
  height: 0;
  left: 0;
  pointer-events: none;
  position: absolute;
  top: 0;
  width: 0;
}

.eeg-signal-style-list-panel__color-button {
  align-items: center;
  background: rgba(15, 23, 42, 0.02);
  border: 1px solid rgba(148, 163, 184, 0.28);
  border-radius: 999px;
  color: #334155;
  cursor: pointer;
  display: inline-flex;
  flex: 0 0 auto;
  gap: 6px;
  min-height: 24px;
  padding: 2px 8px;
}

.eeg-signal-style-list-panel__color-swatch {
  border: 1px solid rgba(15, 23, 42, 0.12);
  border-radius: 999px;
  display: inline-block;
  flex: 0 0 auto;
  height: 10px;
  width: 10px;
}

.eeg-signal-style-list-panel__line-preview {
  border-radius: 2px;
  display: inline-block;
  flex: 0 0 auto;
  height: 3px;
  width: 56px;
}

.eeg-signal-style-list-panel__name {
  color: #0f172a;
  flex: 1 1 auto;
  font-size: 13px;
  line-height: 1.2;
  min-width: 0;
}

.eeg-signal-style-list-panel__editor-card {
  background: linear-gradient(180deg, #ffffff 0%, #f8fafc 100%);
  border: 1px solid rgba(148, 163, 184, 0.32);
  border-radius: 12px;
  box-shadow: 0 18px 38px rgba(15, 23, 42, 0.25);
  max-width: calc(100vw - 18px);
  overflow: hidden;
  width: 320px;
}

.eeg-signal-style-list-panel__editor-header {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: 8px 10px;
}

.eeg-signal-style-list-panel__editor-title {
  color: #0b1220;
  font-size: 14px;
  font-weight: 700;
  line-height: 1.2;
}

.eeg-signal-style-list-panel__editor-body {
  padding: 10px;
}

:deep(.eeg-style-panel-slide-enter-active),
:deep(.eeg-style-panel-slide-leave-active) {
  transition: opacity 0.2s ease, transform 0.2s ease;
}

:deep(.eeg-style-panel-slide-enter-from),
:deep(.eeg-style-panel-slide-leave-to) {
  opacity: 0;
  transform: translateX(20px);
}

:deep(.eeg-style-panel-slide-enter-to),
:deep(.eeg-style-panel-slide-leave-from) {
  opacity: 1;
  transform: translateX(0);
}

@media (max-width: 899px) {
  .eeg-signal-style-list-panel__editor-card {
    width: min(320px, calc(100vw - 18px));
  }
}
</style>
