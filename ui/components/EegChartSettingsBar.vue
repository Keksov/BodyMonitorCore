<template>
  <div class="eeg-chart-settings-bar row items-center no-wrap q-px-sm q-py-xs">
    <!-- Window averaging -->
    <div class="col-auto row items-center q-gutter-xs no-wrap">
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
    </div>

    <q-separator vertical color="grey-7" class="q-mx-sm self-stretch" />

    <!-- Data source -->
    <div class="col-auto row items-center q-gutter-xs no-wrap">
      <span class="text-caption text-grey-5 eeg-chart-settings-bar__label">{{ $t('monitoring.eegSourceLabel') }}</span>
      <q-btn-group flat>
        <q-btn
          dense
          flat
          size="sm"
          :color="dataSource === 'bands' ? 'secondary' : undefined"
          :label="$t('monitoring.dataSource.bands')"
          @click="handleDataSourceChange('bands')"
        />
        <q-btn
          dense
          flat
          size="sm"
          :color="dataSource === 'algo-bp' ? 'secondary' : undefined"
          :label="$t('monitoring.dataSource.algoBp')"
          @click="handleDataSourceChange('algo-bp')"
        />
      </q-btn-group>
    </div>

    <q-separator vertical color="grey-7" class="q-mx-sm self-stretch" />

    <!-- Scale -->
    <div v-if="dataSource !== 'algo-bp'" class="col-auto row items-center q-gutter-xs no-wrap">
      <span class="text-caption text-grey-5 eeg-chart-settings-bar__label">{{ $t('monitoring.eegScaleLabel') }}</span>
      <q-select
        dense
        outlined
        hide-bottom-space
        options-dense
        emit-value
        map-options
        class="eeg-chart-settings-bar__scale-select"
        :model-value="scaleMode"
        :options="scaleOptions"
        @update:model-value="handleScaleChange"
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
    </div>

    <!-- Help icon -->
    <q-btn
      round
      flat
      dense
      size="sm"
      icon="help_outline"
      color="grey-5"
      class="q-ml-xs"
      @click="showHelp = true"
    />

    <!-- Help dialog -->
    <q-dialog v-model="showHelp">
      <q-card style="min-width: 400px; max-width: 540px">
        <q-card-section class="row items-center q-pb-none">
          <div class="text-h6">{{ $t('monitoring.eegSettingsHelp.title') }}</div>
          <q-space />
          <q-btn icon="close" flat round dense v-close-popup />
        </q-card-section>

        <q-card-section class="q-pt-md q-pb-lg">
          <div class="text-subtitle2 text-primary q-mb-xs">{{ $t('monitoring.eegWindowLabel') }}</div>
          <div class="text-body2 text-grey-4 q-mb-sm">{{ $t('monitoring.eegSettingsHelp.windowIntro') }}</div>
          <ul class="q-mt-none q-mb-md eeg-chart-settings-bar__help-list text-body2">
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

          <div class="text-subtitle2 text-primary q-mb-xs">{{ $t('monitoring.eegScaleLabel') }}</div>
          <div class="text-body2 text-grey-4 q-mb-sm">{{ $t('monitoring.eegSettingsHelp.scaleIntro') }}</div>
          <ul class="q-mt-none eeg-chart-settings-bar__help-list text-body2">
            <li class="q-mb-xs">
              <span class="text-weight-medium">{{ $t('monitoring.bandScale.raw') }}</span>
              &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.scaleRaw') }}
            </li>
            <li class="q-mb-xs">
              <span class="text-weight-medium">{{ $t('monitoring.bandScale.normalized') }}</span>
              &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.scaleNormalized') }}
            </li>
            <li>
              <span class="text-weight-medium">{{ $t('monitoring.bandScale.calibrated') }}</span>
              &nbsp;&mdash; {{ $t('monitoring.eegSettingsHelp.scaleCalibrated') }}
            </li>
          </ul>
        </q-card-section>
      </q-card>
    </q-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import type { EegBandScaleMode, EegDataSource } from '../stores/preferences'

const props = defineProps<{
  readonly windowSec: number
  readonly scaleMode: EegBandScaleMode
  readonly canUseCalibrated: boolean
  readonly calibratedTooltip?: string | null
  readonly dataSource: EegDataSource
}>()

const emit = defineEmits<{
  (e: 'update:windowSec', value: number): void
  (e: 'update:scaleMode', value: EegBandScaleMode): void
  (e: 'update:dataSource', value: EegDataSource): void
}>()

const { t } = useI18n()

const showHelp = ref(false)

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

interface ScaleOption {
  value: EegBandScaleMode
  label: string
  disable?: boolean
}

const scaleOptions = computed<ScaleOption[]>(() => [
  { value: 'raw', label: t('monitoring.bandScale.raw') },
  { value: 'normalized', label: t('monitoring.bandScale.normalized') },
  { value: 'calibrated', label: t('monitoring.bandScale.calibrated'), disable: !props.canUseCalibrated },
])

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

function handleScaleChange(value: EegBandScaleMode): void {
  emit('update:scaleMode', value)
}

function handleDataSourceChange(value: EegDataSource): void {
  emit('update:dataSource', value)
}
</script>

<style scoped>
.eeg-chart-settings-bar {
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
}

.eeg-chart-settings-bar__label {
  white-space: nowrap;
}

.eeg-chart-settings-bar__window-select {
  width: 120px;
}

.eeg-chart-settings-bar__scale-select {
  min-width: 140px;
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
</style>
