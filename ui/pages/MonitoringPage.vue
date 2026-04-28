<template>
  <q-page padding class="monitoring-page">
    <div class="monitoring-page__content column q-gutter-md">
      <q-card flat bordered class="monitoring-page__card column no-wrap">
        <q-card-section class="row items-start justify-between q-gutter-md">
          <div>
            <div class="text-h6">{{ $t('monitoring.chartTitle') }}</div>
            <div class="text-caption text-grey-5">
              {{ replay.isReplayMode ? $t('monitoring.chartLoadedSubtitle') : $t('monitoring.chartLiveSubtitle') }}
            </div>
          </div>

          <div class="monitoring-page__header-side column items-end">
            <div v-if="replay.isReplayMode" class="monitoring-page__loaded-summary row items-center justify-end q-gutter-sm">
              <div class="monitoring-page__loaded-name text-caption text-amber-4 ellipsis" :title="replay.replaySessionName">
                {{ replay.replaySessionName }}
              </div>
            </div>

            <q-chip v-else dense color="secondary" text-color="white">
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

            <div v-if="!replay.isReplayMode" class="col-auto">
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

            <div v-if="hasEegData && preferences.eegDisplayMode === 'bands'" class="col-auto row items-center q-gutter-sm">
              <q-input
                dense
                outlined
                hide-bottom-space
                type="number"
                min="1"
                input-class="text-right"
                class="monitoring-page__band-window"
                :model-value="preferences.eegBandWindowSec"
                :label="$t('monitoring.bandWindowSec')"
                @update:model-value="updateBandWindowSec"
              />

              <q-btn-group flat>
                <q-btn
                  dense
                  flat
                  no-caps
                  :color="preferences.eegBandScaleMode === 'normalized' ? 'secondary' : undefined"
                  :label="$t('monitoring.bandScale.normalized')"
                  @click="preferences.eegBandScaleMode = 'normalized'"
                />
                <q-btn
                  dense
                  flat
                  no-caps
                  :color="preferences.eegBandScaleMode === 'absolute' ? 'secondary' : undefined"
                  :label="$t('monitoring.bandScale.absolute')"
                  @click="preferences.eegBandScaleMode = 'absolute'"
                />
              </q-btn-group>

              <q-chip v-if="bandWindowRangeLabel !== null" dense color="grey-9" text-color="grey-3">
                {{ bandWindowRangeLabel }}
              </q-chip>
            </div>

            <div v-if="replay.isReplayMode" class="col-auto row items-center q-gutter-xs">
              <span class="text-caption text-grey-5">{{ $t('monitoring.replaySpeed') }}</span>

              <q-btn-group flat>
                <q-btn
                  v-for="speed in replaySpeedOptions"
                  :key="speed"
                  dense
                  flat
                  no-caps
                  :disable="replay.replayStatus !== 'playing'"
                  :color="replay.replaySpeed === speed ? 'secondary' : undefined"
                  :label="`${speed}x`"
                  @click="replay.setReplaySpeed(speed)"
                />
              </q-btn-group>
            </div>
          </div>
        </q-card-section>

        <q-card-section class="q-pt-none monitoring-page__chart-section">
          <template v-if="preferences.eegDisplayMode === 'bands' && hasEegData && activeChartData !== null">
            <eeg-band-bar-chart
              class="monitoring-page__chart"
              :data="activeChartData"
              :window-sec="preferences.eegBandWindowSec"
              :scale-mode="preferences.eegBandScaleMode"
              :anchor-timestamp-ms="activeBandAnchorTimestampMs"
            />
          </template>

          <!-- Radar mode: show only EegRadarChart -->
          <template v-else-if="preferences.eegDisplayMode === 'radar' && hasEegData && activeChartData !== null">
            <eeg-radar-chart
              class="monitoring-page__chart"
              :data="activeChartData"
            />
          </template>

          <!-- Standard modes: DeviceDataChart (may exclude EEG panel in radar mode if no ECG/breath) -->
          <template v-else>
            <device-data-chart
              class="monitoring-page__chart"
              v-if="activeChartData !== null && hasActiveChartData"
              :data="activeChartData"
              :mode="replay.isReplayMode ? 'loaded' : 'live'"
              :eeg-mode="preferences.eegDisplayMode"
              :viewport-preset="viewportPreset"
              :viewport-token="viewportToken"
            />

            <div v-else-if="isChartLoading" class="monitoring-page__chart-placeholder column items-center justify-center text-grey-5">
              <q-spinner-hourglass size="lg" color="secondary" />
              <div class="q-mt-sm">{{ $t('monitoring.chartLoading') }}</div>
            </div>

            <div v-else class="monitoring-page__chart-placeholder column items-center justify-center text-grey-5">
              <div class="text-subtitle2">{{ $t('monitoring.chartEmptyTitle') }}</div>
              <div class="text-caption q-mt-xs text-center">
                {{ replay.isReplayMode ? $t('monitoring.chartEmptyLoaded') : $t('monitoring.chartEmptyLive') }}
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
import { computed, defineAsyncComponent, ref, watch } from 'vue'
import SessionControls from '../components/SessionControls.vue'
import { useReplay } from '../composables/use-replay'
import { useSessionStore } from '../stores/session'
import { usePreferencesStore } from '../stores/preferences'
import { hasLogChartData } from '../../../SharedPasCore/ts/log-chart'
import { useI18n } from 'vue-i18n'
import type { EegDisplayMode } from '../stores/preferences'

type ChartViewportPreset = 'fit' | 'recent'

const DeviceDataChart = defineAsyncComponent(() => import('../components/DeviceDataChart.vue'))
const EegRadarChart = defineAsyncComponent(() => import('../components/EegRadarChart.vue'))
const EegBandBarChart = defineAsyncComponent(() => import('../components/EegBandBarChart.vue'))

const session = useSessionStore()
const preferences = usePreferencesStore()
const { t } = useI18n()
const replay = useReplay()
const viewportPreset = ref<ChartViewportPreset>(replay.isReplayMode ? 'fit' : 'recent')
const viewportToken = ref(0)

const activeChartData = computed(() => replay.isReplayMode ? replay.replayChartData : session.chartData)
const hasActiveChartData = computed(() => hasLogChartData(activeChartData.value))
const hasEegData = computed(() =>
  activeChartData.value?.series.some((s) => s.panel === 'eeg' && s.points.length > 0) ?? false,
)
const isChartLoading = computed(() => replay.isReplayMode && replay.replayChartLoading)
const isStandaloneEegMode = computed(() => {
  return preferences.eegDisplayMode === 'radar' || preferences.eegDisplayMode === 'bands'
})
const activeBandAnchorTimestampMs = computed<number | undefined>(() => {
  if (replay.isReplayMode) {
    return replay.replayCursorTimestampMs ?? activeChartData.value?.minTimestampMs ?? undefined
  }

  return activeChartData.value?.maxTimestampMs ?? undefined
})

const bandWindowRangeLabel = computed(() => {
  const anchorTimestampMs = activeBandAnchorTimestampMs.value
  if (anchorTimestampMs === undefined) {
    return null
  }

  const windowStartTimestampMs = anchorTimestampMs - preferences.eegBandWindowSec * 1000
  const formatter = new Intl.DateTimeFormat(undefined, {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })

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

const replaySpeedOptions = [1, 2, 4, 10] as const

const eegModeOptions = computed<EegModeOption[]>(() => [
  { value: 'lines', icon: 'show_chart', tooltip: t('monitoring.eegMode.lines') },
  { value: 'subpanels', icon: 'splitscreen', tooltip: t('monitoring.eegMode.subpanels') },
  { value: 'stacked', icon: 'stacked_bar_chart', tooltip: t('monitoring.eegMode.stacked') },
  { value: 'heatmap', icon: 'gradient', tooltip: t('monitoring.eegMode.heatmap') },
  { value: 'bands', icon: 'bar_chart', tooltip: t('monitoring.eegMode.bands') },
  { value: 'radar', icon: 'radar', tooltip: t('monitoring.eegMode.radar') },
])
const chartError = computed(() => replay.isReplayMode ? replay.replayChartError ?? replay.replayError : session.lastError)
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

watch(() => replay.isReplayMode, (isReplayMode) => {
  viewportPreset.value = isReplayMode ? 'fit' : 'recent'
  viewportToken.value += 1
})

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

  if (!Number.isFinite(parsed) || parsed < 1) {
    return
  }

  preferences.eegBandWindowSec = Math.max(1, Math.trunc(parsed))
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

.monitoring-page__loaded-summary {
  max-width: 100%;
  min-width: 0;
}

.monitoring-page__loaded-name {
  min-width: 0;
  max-width: 100%;
}

.monitoring-page__session-controls {
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
  flex: 1 1 auto;
  flex-direction: column;
  min-height: 0;
}

.monitoring-page__chart {
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

  .monitoring-page__loaded-summary {
    max-width: 100%;
    width: 100%;
    justify-content: space-between;
  }
}
</style>
