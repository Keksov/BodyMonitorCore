<template>
  <q-page padding class="monitoring-page">
    <div class="monitoring-page__content column q-gutter-md">
      <q-card flat bordered class="monitoring-page__card column no-wrap">
        <q-card-section class="row items-start justify-between q-gutter-md">
          <div>
            <div class="text-h6">{{ $t('monitoring.chartTitle') }}</div>
            <div class="text-caption text-grey-5">
              {{ $t('monitoring.chartLiveSubtitle') }}
            </div>
          </div>

          <div class="monitoring-page__header-side column items-end">
            <q-chip dense color="secondary" text-color="white">
              {{ $t('monitoring.modeLive') }}
            </q-chip>
            <session-controls align="end" class="monitoring-page__session-controls" />
          </div>
        </q-card-section>

        <q-separator />

        <q-card-section class="q-py-sm">
          <div class="row items-center q-col-gutter-sm q-row-gutter-sm monitoring-page__toolbar">
            <div class="col-auto">
              <q-btn
                dense
                flat
                icon="fit_screen"
                :label="$t('monitoring.fitRange')"
                :disable="!hasActiveChartData || isStandaloneEegMode"
                @click="requestViewport('fit')"
              />
            </div>

            <div class="col-auto">
              <q-btn
                dense
                flat
                icon="schedule"
                :label="$t('monitoring.recentWindow')"
                :disable="!hasActiveChartData || isStandaloneEegMode"
                @click="requestViewport('recent')"
              />
            </div>

            <div v-if="activeSeriesCount > 0" class="col-auto">
              <q-chip dense color="grey-9" text-color="grey-3">
                {{ $t('monitoring.stats.signals', { count: activeSeriesCount }) }}
              </q-chip>
            </div>

            <div v-if="activePointCount > 0" class="col-auto">
              <q-chip dense color="grey-9" text-color="grey-3">
                {{ $t('monitoring.stats.points', { count: formattedPointCount }) }}
              </q-chip>
            </div>

            <div v-if="rangeLabel !== null" class="col text-caption text-grey-5 ellipsis">
              {{ rangeLabel }}
            </div>

            <div v-if="hasEegData" class="col-auto">
              <q-btn-group flat>
                <q-btn
                  v-for="opt in eegModeOptions"
                  :key="opt.value"
                  dense
                  flat
                  :icon="opt.icon"
                  :color="preferences.eegDisplayMode === opt.value ? 'secondary' : undefined"
                  @click="preferences.eegDisplayMode = opt.value"
                >
                  <q-tooltip>{{ opt.tooltip }}</q-tooltip>
                </q-btn>
              </q-btn-group>
            </div>

            <div v-if="hasEegData" class="col-auto row items-center q-gutter-sm">
              <eeg-chart-settings-bar
                :window-sec="preferences.eegBandWindowSec"
                :scale-mode="preferences.eegBandScaleMode"
                :can-use-calibrated="canUseCalibratedScale"
                :calibrated-tooltip="calibratedUnavailableMessage"
                @update:window-sec="updateBandWindowSec"
                @update:scale-mode="preferences.eegBandScaleMode = $event"
              />

              <q-chip v-if="bandWindowRangeLabel !== null" dense color="grey-9" text-color="grey-3">
                {{ bandWindowRangeLabel }}
              </q-chip>

              <q-chip
                v-if="!canUseCalibratedScale"
                dense
                color="warning"
                text-color="black"
              >
                {{ calibratedUnavailableMessage }}
              </q-chip>

              <q-chip
                v-if="canUseCalibratedScale && preferences.eegBandScaleMode === 'calibrated'"
                dense
                color="blue-grey-8"
                text-color="blue-grey-2"
              >
                {{ $t('monitoring.calibration.deltaCaveat') }}
              </q-chip>
            </div>
          </div>
        </q-card-section>

        <q-card-section class="q-pt-none monitoring-page__chart-section">
          <template v-if="isStandaloneEegMode && hasEegData && activeChartData !== null">
            <div v-if="showGnauralSchedule" class="monitoring-page__standalone-layout" ref="splitterContainerEl">
              <q-splitter
                horizontal
                class="monitoring-page__splitter"
                v-model="eegSplitPx"
                unit="px"
                :limits="splitterLimits"
              >
                <template #before>
                  <div class="monitoring-page__eeg-split">
                    <eeg-current-readings-chart
                      v-if="preferences.eegDisplayMode === 'bands'"
                      class="monitoring-page__chart"
                      :data="activeChartData"
                      :window-sec="preferences.eegBandWindowSec"
                      :scale-mode="preferences.eegBandScaleMode"
                      :calibration-profile="activeEegCalibrationProfile"
                      :anchor-timestamp-ms="activeBandAnchorTimestampMs"
                      :force-no-signal="isSelectedEegOffline"
                      show-signal-badge
                    />

                    <eeg-radar-chart
                      v-else
                      class="monitoring-page__chart"
                      :data="activeChartData"
                      :anchor-timestamp-ms="activeBandAnchorTimestampMs"
                      :window-sec="preferences.eegBandWindowSec"
                      :scale-mode="preferences.eegBandScaleMode"
                      :calibration-profile="activeEegCalibrationProfile"
                    />
                  </div>
                </template>

                <template #after>
                  <div class="monitoring-page__schedule-pane">
                    <gnaural-schedule-view
                      class="monitoring-page__schedule"
                      :schedule="currentGnauralSchedule"
                      :file-path="currentGnauralFilePath"
                      :position-sec="monitoringSchedulePositionSec"
                      :transport-state="monitoringScheduleTransportState"
                      :track-state-busy="true"
                      :can-seek="monitoringCanSeek"
                      ui-state-scope="monitoring-page"
                      @seek="handleMonitoringAudioSeek"
                    >
                      <template #transportControls>
                        <gnaural-transport-controls
                          :start-stop-icon="monitoringStartStopIcon"
                          :start-stop-label="monitoringStartStopLabel"
                          :start-stop-color="monitoringStartStopColor"
                          :start-stop-flat="monitoringStartStopFlat"
                          :start-stop-disabled="monitoringStartStopDisabled"
                          :pause-resume-icon="monitoringPauseResumeIcon"
                          :pause-resume-label="monitoringPauseResumeLabel"
                          :pause-resume-disabled="monitoringPauseResumeDisabled"
                          @start-stop="handleMonitoringStartStop"
                          @pause-resume="handleMonitoringPauseResume"
                        />
                      </template>
                    </gnaural-schedule-view>
                  </div>
                </template>
              </q-splitter>
            </div>

            <template v-else>
              <eeg-current-readings-chart
                v-if="preferences.eegDisplayMode === 'bands'"
                class="monitoring-page__chart"
                :data="activeChartData"
                :window-sec="preferences.eegBandWindowSec"
                :scale-mode="preferences.eegBandScaleMode"
                :calibration-profile="activeEegCalibrationProfile"
                :anchor-timestamp-ms="activeBandAnchorTimestampMs"
                :force-no-signal="isSelectedEegOffline"
                show-signal-badge
              />

              <eeg-radar-chart
                v-else
                class="monitoring-page__chart"
                :data="activeChartData"
                :anchor-timestamp-ms="activeBandAnchorTimestampMs"
                :window-sec="preferences.eegBandWindowSec"
                :scale-mode="preferences.eegBandScaleMode"
                :calibration-profile="activeEegCalibrationProfile"
              />
            </template>
          </template>

          <template v-else>
            <device-data-chart
              class="monitoring-page__chart"
              v-if="activeChartData !== null && hasActiveChartData"
              :data="activeChartData"
              mode="live"
              :eeg-mode="preferences.eegDisplayMode"
              :viewport-preset="viewportPreset"
              :viewport-token="viewportToken"
            />

            <div v-else class="monitoring-page__chart-placeholder column items-center justify-center text-grey-5">
              <div class="text-subtitle2">{{ $t('monitoring.chartEmptyTitle') }}</div>
              <div class="text-caption q-mt-xs text-center">
                {{ $t('monitoring.chartEmptyLive') }}
              </div>
            </div>
          </template>

          <div v-if="chartError !== null" class="text-negative q-mt-md">
            {{ chartError }}
          </div>
        </q-card-section>
      </q-card>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { computed, defineAsyncComponent, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import SessionControls from '../components/SessionControls.vue'
import { useEegDiagnosticsPump } from '../composables/use-eeg-diagnostics-pump'
import { useChartDataSource } from '../composables/use-chart-data-source'
import { useSessionStore } from '../stores/session'
import { usePreferencesStore } from '../stores/preferences'
import { useDeviceStore } from '../stores/device'
import { hasLogChartData } from '../../../SharedPasCore/ts/log-chart'
import { useAudioStore } from '../../../GnauralCore/ui/stores/audio'
import { useAudioTransport } from '../../../GnauralCore/ui/composables/use-audio-transport'
import type { EegDisplayMode } from '../stores/preferences'

type ChartViewportPreset = 'fit' | 'recent'

const DeviceDataChart = defineAsyncComponent(() => import('../components/DeviceDataChart.vue'))
const EegRadarChart = defineAsyncComponent(() => import('../components/EegRadarChart.vue'))
const EegCurrentReadingsChart = defineAsyncComponent(() => import('../components/EegCurrentReadingsChart.vue'))
const EegChartSettingsBar = defineAsyncComponent(() => import('../components/EegChartSettingsBar.vue'))
const GnauralScheduleView = defineAsyncComponent(() => import('../../../GnauralCore/ui/components/GnauralScheduleView.vue'))
const GnauralTransportControls = defineAsyncComponent(() => import('../../../GnauralCore/ui/components/GnauralTransportControls.vue'))

const session = useSessionStore()
const preferences = usePreferencesStore()
const device = useDeviceStore()
const audio = useAudioStore()
const { t } = useI18n()
const audioTransport = useAudioTransport()
const { activeChartData } = useChartDataSource()
useEegDiagnosticsPump()
const viewportPreset = ref<ChartViewportPreset>('recent')
const viewportToken = ref(0)

const EEG_SPLIT_STORAGE_KEY = 'monitoring-page-eeg-split-px'
const EEG_SPLIT_DEFAULT = 400
const EEG_SPLIT_MIN = 320
const eegSplitPx = ref(
  parseFloat(localStorage.getItem(EEG_SPLIT_STORAGE_KEY) ?? String(EEG_SPLIT_DEFAULT))
)
watch(eegSplitPx, (value) => {
  localStorage.setItem(EEG_SPLIT_STORAGE_KEY, String(value))
})

const splitterContainerEl = ref<HTMLDivElement | null>(null)
const splitterContainerHeight = ref(0)
const splitterLimits = computed<[number, number]>(() => {
  return [
    EEG_SPLIT_MIN,
    Math.max(EEG_SPLIT_MIN, splitterContainerHeight.value - EEG_SPLIT_MIN),
  ]
})

let splitterContainerObserver: ResizeObserver | null = null
onMounted(() => {
  splitterContainerObserver = new ResizeObserver((entries) => {
    splitterContainerHeight.value = entries[0]?.contentRect.height ?? 0
  })

  watch(
    splitterContainerEl,
    (element) => {
      splitterContainerObserver!.disconnect()
      if (element !== null) {
        splitterContainerObserver!.observe(element)
      }
    },
    { immediate: true },
  )
})

onBeforeUnmount(() => {
  splitterContainerObserver?.disconnect()
  splitterContainerObserver = null
})

const hasActiveChartData = computed(() => hasLogChartData(activeChartData.value))
const hasEegData = computed(() =>
  activeChartData.value?.series.some((series) => series.panel === 'eeg' && series.points.length > 0) ?? false,
)

const selectedEegMac = computed(() => {
  return device.getSelectedMac('eeg')
})

const activeEegCalibrationProfile = computed(() => {
  if (selectedEegMac.value === null) {
    return null
  }

  return device.getEegCalibrationProfile(selectedEegMac.value)
})

const missingCalibrationModesLabel = computed(() => {
  const completedModes = activeEegCalibrationProfile.value?.completedModes
  if (completedModes === undefined) {
    return t('monitoring.calibration.requiredModes')
  }

  const modes: string[] = []
  if (!completedModes.attention) {
    modes.push(t('calibration.hub.attentionButton'))
  }
  if (!completedModes.alphaRelaxation) {
    modes.push(t('calibration.hub.relaxationButton'))
  }
  if (!completedModes.drowse) {
    modes.push(t('calibration.hub.drowseButton'))
  }

  return modes.join(', ')
})

const canUseCalibratedScale = computed(() => {
  return activeEegCalibrationProfile.value?.isComplete === true
})

const isSelectedEegOffline = computed(() => {
  if (selectedEegMac.value === null) {
    return false
  }

  return session.isDeviceOffline(selectedEegMac.value)
})

const calibratedUnavailableMessage = computed(() => {
  if (selectedEegMac.value === null) {
    return t('monitoring.calibration.noDevice')
  }

  if (activeEegCalibrationProfile.value === null) {
    return t('monitoring.calibration.profileMissing')
  }

  return t('monitoring.calibration.incompleteMissing', { modes: missingCalibrationModesLabel.value })
})

const isStandaloneEegMode = true

const currentGnauralSchedule = computed(() => {
  return audio.gnauralSchedule
})

const currentGnauralFilePath = computed(() => {
  return audio.displayFilePath
})

const showGnauralSchedule = computed(() => {
  return currentGnauralSchedule.value !== null
})

const activeBandAnchorTimestampMs = computed<number | undefined>(() => {
  return activeChartData.value?.maxTimestampMs ?? undefined
})

const monitoringSchedulePositionSec = computed(() => {
  return audioTransport.displayedPositionSec.value
})

const monitoringScheduleTransportState = computed(() => {
  return audio.transportState
})

const monitoringCanSeek = computed(() => {
  return audioTransport.canSeek.value
})

const monitoringStartStopLabel = computed(() => {
  return audioTransport.startStopButtonLabel.value
})

const monitoringStartStopIcon = computed(() => {
  return audioTransport.startStopButtonIcon.value
})

const monitoringStartStopColor = computed(() => {
  return audioTransport.startStopButtonColor.value
})

const monitoringStartStopFlat = computed(() => {
  return audioTransport.startStopButtonFlat.value
})

const monitoringStartStopDisabled = computed(() => {
  if (audio.canStop) {
    return false
  }

  return currentGnauralFilePath.value === null
})

const monitoringPauseResumeLabel = computed(() => {
  return audioTransport.pauseResumeButtonLabel.value
})

const monitoringPauseResumeIcon = computed(() => {
  return audioTransport.pauseResumeButtonIcon.value
})

const monitoringPauseResumeDisabled = computed(() => {
  return audioTransport.pauseResumeDisabled.value
})

const bandWindowRangeLabel = computed(() => {
  const anchorTimestampMs = activeBandAnchorTimestampMs.value
  if (anchorTimestampMs === undefined) {
    return null
  }

  const formatter = new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })

  if (preferences.eegBandWindowSec === 0) {
    return t('monitoring.bandLatestPoint', { time: formatter.format(new Date(anchorTimestampMs)) })
  }

  const windowStartTimestampMs = anchorTimestampMs - preferences.eegBandWindowSec * 1000
  return t('monitoring.bandWindowRange', {
    start: formatter.format(new Date(windowStartTimestampMs)),
    end: formatter.format(new Date(anchorTimestampMs)),
  })
})

interface EegModeOption {
  readonly value: EegDisplayMode
  readonly icon: string
  readonly tooltip: string
}

const eegModeOptions = computed<EegModeOption[]>(() => [
  { value: 'bands', icon: 'bar_chart', tooltip: t('monitoring.eegMode.bands') },
  { value: 'radar', icon: 'radar', tooltip: t('monitoring.eegMode.radar') },
])

const chartError = computed(() => session.lastError)
const activeSeriesCount = computed(() => activeChartData.value?.series.filter((series) => series.points.length > 0).length ?? 0)
const activePointCount = computed(() => activeChartData.value?.series.reduce((total, series) => total + series.points.length, 0) ?? 0)
const formattedPointCount = computed(() => new Intl.NumberFormat().format(activePointCount.value))

const rangeLabel = computed(() => {
  const snapshot = activeChartData.value
  if (snapshot === null || snapshot.minTimestampMs === null || snapshot.maxTimestampMs === null) {
    return null
  }

  const formatter = new Intl.DateTimeFormat(undefined, {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })

  return `${formatter.format(new Date(snapshot.minTimestampMs))} - ${formatter.format(new Date(snapshot.maxTimestampMs))}`
})

watch(canUseCalibratedScale, (isAvailable) => {
  if (!isAvailable && preferences.eegBandScaleMode === 'calibrated') {
    preferences.eegBandScaleMode = 'raw'
  }
}, { immediate: true })

function requestViewport(preset: ChartViewportPreset) {
  viewportPreset.value = preset
  viewportToken.value += 1
}

function updateBandWindowSec(value: string | number | null) {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 0) {
    return
  }

  preferences.eegBandWindowSec = parsed === 0 ? 0 : Math.max(1, Math.trunc(parsed))
}

function handleMonitoringStartStop() {
  if (audio.canStop) {
    audioTransport.stopPlayback()
    return
  }

  const filePath = currentGnauralFilePath.value
  if (filePath === null) {
    return
  }

  audio.cancelPendingLocalStart()
  audio.stopLocalPlayback()
  audioTransport.sendAudioMessage({ type: 'audio_start', filePath }, t('audio.wsSendFailed'))
}

function handleMonitoringPauseResume() {
  audioTransport.handlePauseResume()
}

function handleMonitoringAudioSeek(value: number) {
  audioTransport.handleSeek(value)
}
</script>

<style scoped>
.monitoring-page {
  display: flex;
  flex-direction: column;
}

.monitoring-page__content {
  flex: 1 1 auto;
  min-height: 0;
}

.monitoring-page__card {
  flex: 1 1 auto;
  min-height: 0;
}

.monitoring-page__header-side {
  max-width: min(56%, 720px);
  min-width: 0;
}

.monitoring-page__session-controls {
  width: 100%;
  max-width: 100%;
}

.monitoring-page__toolbar {
  min-height: 36px;
}

.monitoring-page__band-window {
  width: 132px;
}

.monitoring-page__chart-section {
  display: flex;
  flex: 1 1 0;
  flex-direction: column;
  min-height: 0;
  overflow: hidden;
}

.monitoring-page__standalone-layout {
  display: flex;
  flex: 1 1 auto;
  flex-direction: column;
  min-height: 0;
}

.monitoring-page__splitter {
  flex: 1 1 auto;
  min-height: 0;
}

.monitoring-page__schedule-pane {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}

.monitoring-page__eeg-split {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
}

.monitoring-page__chart {
  flex: 1 1 auto;
  min-height: 0;
}

.monitoring-page__schedule {
  flex: 1 1 auto;
  min-height: 0;
}

.monitoring-page__chart-placeholder {
  flex: 1 1 auto;
  min-height: 320px;
  border: 1px dashed rgba(255, 255, 255, 0.16);
  border-radius: 12px;
}

@media (max-width: 899px) {
  .monitoring-page__header-side {
    max-width: 100%;
    width: 100%;
    align-items: flex-start;
  }
}
</style>