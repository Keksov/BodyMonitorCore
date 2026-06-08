<template>
  <div class="eeg-chart-settings-bar row items-center q-px-sm q-py-xs">
    <!-- Window averaging -->
    <div class="eeg-chart-settings-bar__group col-auto row items-center q-gutter-xs no-wrap">
      <span class="text-caption text-grey-5 eeg-chart-settings-bar__label">{{ $t('monitoring.eegWindowLabel') }}</span>
      <q-select
        dense
        outlined
        hide-bottom-space
        options-dense
        emit-value
        map-options
        class="eeg-chart-settings-bar__window-select"
        :model-value="selectModelValue"
        :options="windowPresetOptions"
        @update:model-value="handlePresetChange"
      />
      <q-input
        v-if="isCustomMode"
        dense
        outlined
        hide-bottom-space
        type="number"
        min="1"
        input-class="text-right"
        class="eeg-chart-settings-bar__custom-input"
        :model-value="customInputValue"
        @update:model-value="handleCustomInputChange"
      />
      <q-btn
        round
        flat
        dense
        size="sm"
        icon="help_outline"
        color="grey-5"
        @click="openHelp('window')"
      />
    </div>

    <q-separator vertical color="grey-7" class="eeg-chart-settings-bar__separator q-mx-sm self-stretch" />

    <!-- Data source -->
    <div class="eeg-chart-settings-bar__group col-auto row items-center q-gutter-xs no-wrap">
      <span class="text-caption text-grey-5 eeg-chart-settings-bar__label">{{ $t('monitoring.eegSourceLabel') }}</span>
      <q-select
        dense
        outlined
        hide-bottom-space
        options-dense
        emit-value
        map-options
        class="eeg-chart-settings-bar__source-select"
        :model-value="dataSource"
        :options="dataSourceOptions"
        @update:model-value="handleDataSourceChange"
      />
      <q-btn
        round
        flat
        dense
        size="sm"
        icon="help_outline"
        color="grey-5"
        @click="openHelp('source')"
      />
    </div>

    <q-separator vertical color="grey-7" class="eeg-chart-settings-bar__separator q-mx-sm self-stretch" />

    <!-- Data correction -->
    <div class="eeg-chart-settings-bar__group col-auto row items-center q-gutter-xs no-wrap">
      <span class="text-caption text-grey-5 eeg-chart-settings-bar__label">{{ $t('monitoring.eegDataCorrectionLabel') }}</span>
      <div class="eeg-chart-settings-bar__scale-wrapper">
        <q-select
          dense
          outlined
          hide-bottom-space
          options-dense
          emit-value
          map-options
          class="eeg-chart-settings-bar__scale-select"
          :model-value="dataCorrection"
          :options="dataCorrectionOptions"
          :disable="isCorrectionDisabled"
          @update:model-value="handleDataCorrectionChange"
        >
          <template #option="scope">
            <div
              v-if="scope.opt.disable"
              class="eeg-chart-settings-bar__disabled-option"
            >
              <q-item v-bind="scope.itemProps">
                <q-item-section>
                  <q-item-label class="text-grey-6">{{ scope.opt.label }}</q-item-label>
                </q-item-section>
              </q-item>
              <q-tooltip v-if="calibratedTooltip">{{ calibratedTooltip }}</q-tooltip>
            </div>
            <q-item v-else v-bind="scope.itemProps">
              <q-item-section>
                <q-item-label>{{ scope.opt.label }}</q-item-label>
              </q-item-section>
            </q-item>
          </template>
        </q-select>
        <q-tooltip v-if="isCorrectionDisabled">
          {{ $t('monitoring.eegSettingsHelp.correctionUnavailableForAlgoBp') }}
        </q-tooltip>
      </div>
      <q-btn
        round
        flat
        dense
        size="sm"
        icon="help_outline"
        color="grey-5"
        @click="openHelp('correction')"
      />
    </div>

    <!-- Help dialog -->
    <q-dialog v-model="showHelp">
      <q-card style="min-width: 360px; max-width: 520px">
        <q-card-section class="row items-center q-pb-none">
          <div class="text-h6">{{ activeHelpTitle }}</div>
          <q-space />
          <q-btn icon="close" flat round dense v-close-popup />
        </q-card-section>

        <q-card-section class="q-pt-md q-pb-lg">
          <template v-if="activeHelpTopic === 'window'">
            <div class="text-body2 text-grey-4 q-mb-sm">{{ $t('monitoring.eegSettingsHelp.windowIntro') }}</div>
            <ul class="q-mt-none q-mb-none eeg-chart-settings-bar__help-list text-body2">
              <li class="q-mb-xs">
                <span class="text-weight-medium">{{ $t('monitoring.eegWindow.noAveraging') }}</span>
                &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.windowNoAveraging') }}
              </li>
              <li class="q-mb-xs">
                <span class="text-weight-medium">{{ $t('monitoring.eegWindow.sec5') }}, {{ $t('monitoring.eegWindow.sec10') }}, {{ $t('monitoring.eegWindow.sec30') }}, {{ $t('monitoring.eegWindow.min1') }}</span>
                &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.windowPresets') }}
              </li>
              <li>
                <span class="text-weight-medium">{{ $t('monitoring.eegWindow.custom') }}</span>
                &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.windowCustom') }}
              </li>
            </ul>
          </template>

          <template v-else-if="activeHelpTopic === 'source'">
            <div class="text-body2 text-grey-4 q-mb-sm">{{ $t('monitoring.eegSettingsHelp.sourceIntro') }}</div>
            <ul class="q-mt-none q-mb-none eeg-chart-settings-bar__help-list text-body2">
              <li class="q-mb-xs">
                <span class="text-weight-medium">{{ $t('monitoring.dataSource.bands') }}</span>
                &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.sourceBands') }}
              </li>
              <li>
                <span class="text-weight-medium">{{ $t('monitoring.dataSource.algoBp') }}</span>
                &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.sourceAlgoBp') }}
              </li>
            </ul>
          </template>

          <template v-else>
            <div class="text-body2 text-grey-4 q-mb-sm">{{ $t('monitoring.eegSettingsHelp.correctionIntro') }}</div>
            <ul class="q-mt-none q-mb-none eeg-chart-settings-bar__help-list text-body2">
              <li class="q-mb-xs">
                <span class="text-weight-medium">{{ $t('monitoring.dataCorrection.raw') }}</span>
                &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.correctionRaw') }}
              </li>
              <li class="q-mb-xs">
                <span class="text-weight-medium">{{ $t('monitoring.dataCorrection.calibrated') }}</span>
                &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.correctionCalibrated') }}
              </li>
              <li>
                {{ $t('monitoring.eegSettingsHelp.correctionUnavailableForAlgoBp') }}
              </li>
            </ul>
          </template>
        </q-card-section>
      </q-card>
    </q-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import type { EegDataCorrection, EegDataSource } from '../stores/preferences'

const props = defineProps<{
  readonly windowSec: number
  readonly dataCorrection: EegDataCorrection
  readonly canUseCalibrated: boolean
  readonly calibratedTooltip?: string | null
  readonly dataSource: EegDataSource
}>()

const emit = defineEmits<{
  (e: 'update:windowSec', value: number): void
  (e: 'update:dataCorrection', value: EegDataCorrection): void
  (e: 'update:dataSource', value: EegDataSource): void
}>()

const { t } = useI18n()

type HelpTopic = 'window' | 'source' | 'correction'

const showHelp = ref(false)
const activeHelpTopic = ref<HelpTopic>('window')

type NumericPreset = 0 | 5 | 10 | 30 | 60
const NUMERIC_PRESETS: readonly NumericPreset[] = [0, 5, 10, 30, 60]

const windowPresetOptions = computed(() => [
  { value: 0, label: t('monitoring.eegWindow.noAveraging') },
  { value: 5, label: t('monitoring.eegWindow.sec5') },
  { value: 10, label: t('monitoring.eegWindow.sec10') },
  { value: 30, label: t('monitoring.eegWindow.sec30') },
  { value: 60, label: t('monitoring.eegWindow.min1') },
  { value: 'custom' as const, label: t('monitoring.eegWindow.custom') },
])

interface DataCorrectionOption {
  value: EegDataCorrection
  label: string
  disable?: boolean
}

const dataCorrectionOptions = computed<DataCorrectionOption[]>(() => [
  { value: 'raw', label: t('monitoring.dataCorrection.raw') },
  { value: 'calibrated', label: t('monitoring.dataCorrection.calibrated'), disable: !props.canUseCalibrated },
])

interface DataSourceOption {
  value: EegDataSource
  label: string
}

const dataSourceOptions = computed<DataSourceOption[]>(() => [
  { value: 'bands', label: t('monitoring.dataSource.bands') },
  { value: 'algo-bp', label: t('monitoring.dataSource.algoBp') },
])

const isCorrectionDisabled = computed(() => props.dataSource === 'algo-bp')

const activeHelpTitle = computed(() => {
  if (activeHelpTopic.value === 'window') {
    return t('monitoring.eegWindowLabel')
  }

  if (activeHelpTopic.value === 'source') {
    return t('monitoring.eegSourceLabel')
  }

  return t('monitoring.eegDataCorrectionLabel')
})

function isNumericPreset(v: number): v is NumericPreset {
  return (NUMERIC_PRESETS as readonly number[]).includes(v)
}

const isCustomMode = ref(!isNumericPreset(props.windowSec))
const customInputValue = ref<number>(isNumericPreset(props.windowSec) ? 10 : Math.max(1, props.windowSec))

// Keep custom input synchronized when external windowSec changes
watch(() => props.windowSec, (newValue) => {
  if (!isNumericPreset(newValue)) {
    isCustomMode.value = true
    customInputValue.value = newValue
  } else if (isCustomMode.value) {
    // External change switched us back to a preset value — exit custom mode
    isCustomMode.value = false
  }
})

const selectModelValue = computed(() => {
  return isCustomMode.value ? 'custom' : props.windowSec as NumericPreset
})

function handlePresetChange(value: NumericPreset | 'custom') {
  if (value === 'custom') {
    isCustomMode.value = true
    return
  }
  isCustomMode.value = false
  emit('update:windowSec', value)
}

function handleCustomInputChange(value: string | number | null) {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 1) {
    return
  }

  const validated = Math.max(1, Math.trunc(parsed))
  customInputValue.value = validated
  emit('update:windowSec', validated)
}

function handleDataCorrectionChange(value: EegDataCorrection): void {
  emit('update:dataCorrection', value)
}

function handleDataSourceChange(value: EegDataSource): void {
  emit('update:dataSource', value)
}

function openHelp(topic: HelpTopic): void {
  activeHelpTopic.value = topic
  showHelp.value = true
}
</script>

<style scoped>
.eeg-chart-settings-bar {
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
  flex-wrap: nowrap;
}

.eeg-chart-settings-bar__label {
  white-space: nowrap;
}

.eeg-chart-settings-bar__group {
  min-width: 0;
}

.eeg-chart-settings-bar__window-select {
  width: 120px;
  max-width: 100%;
}

.eeg-chart-settings-bar__source-select {
  width: 220px;
  min-width: 220px;
  max-width: 100%;
}

.eeg-chart-settings-bar__scale-select {
  width: 140px;
  min-width: 140px;
  max-width: 100%;
}

.eeg-chart-settings-bar__scale-wrapper {
  position: relative;
}

.eeg-chart-settings-bar__custom-input {
  width: 72px;
}

.eeg-chart-settings-bar__disabled-option {
  position: relative;
}

.eeg-chart-settings-bar__help-list {
  padding-left: 20px;
  line-height: 1.7;
}

@media (max-width: 899px) {
  .eeg-chart-settings-bar {
    align-items: stretch;
    flex-wrap: wrap;
  }

  .eeg-chart-settings-bar__group {
    width: 100%;
  }

  .eeg-chart-settings-bar__separator {
    display: none;
  }

  .eeg-chart-settings-bar__window-select,
  .eeg-chart-settings-bar__source-select,
  .eeg-chart-settings-bar__scale-wrapper,
  .eeg-chart-settings-bar__scale-select {
    flex: 1 1 auto;
    min-width: 0;
    width: auto;
  }
}
</style>
