<template>
  <eeg-chart-side-panel-layout
    ref="sidePanelLayoutRef"
    :ui-state-scope="uiStateScope"
    storage-key="eeg-shared-side-panel-visible"
    :panel-title="t('monitoring.eegLine.signalsTitle')"
    :panel-subtitle="signalsSubtitleText"
    :panel-aria-label="t('monitoring.eegLine.signalsTitle')"
    :open-button-label="t('monitoring.eegLine.openPanel')"
    :close-button-label="t('monitoring.eegLine.closePanel')"
    :show-open-button="showSidePanelOpenButton"
  >
    <div ref="chartRoot" class="eeg-line-timeline-chart__canvas" />

    <template #overlay>
      <div
        v-if="showSignalBadge && signalBadgeText !== null"
        class="eeg-line-timeline-chart__badge"
        :style="{ color: signalBadgeColor }"
      >
        {{ signalBadgeText }}
      </div>
    </template>

    <template #panelBody>
      <eeg-signal-style-list-panel
        :entries="signalPanelEntries"
        show-visibility-actions
        @toggle-visibility="handleSignalPanelVisibilityToggle"
        @set-all-visible="setAllSignalsVisible"
      />
    </template>
  </eeg-chart-side-panel-layout>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { use, init, type ECharts } from 'echarts/core'
import { LineChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, DataZoomComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot } from '@protocol'
import EegChartSidePanelLayout from './EegChartSidePanelLayout.vue'
import EegSignalStyleListPanel from './EegSignalStyleListPanel.vue'
import type { EegCalibrationProfile } from '../stores/device'
import type { EegDataCorrection, EegDataSource } from '../stores/preferences'
import { useEegSignalStyleStore, type EegSignalLineType } from '../stores/eeg-signal-style'
import { ALGO_BP_KEYS, EEG_BAND_KEYS, type AlgoBpKey, type EegBandKey, getLatestSeriesValue } from '../services/eeg-band-snapshot'

use([LineChart, GridComponent, TooltipComponent, DataZoomComponent, CanvasRenderer])

interface TimeViewportPayload {
  readonly startSec: number
  readonly endSec: number
}

const AUX_EEG_SERIES_KEYS = ['attention', 'meditation', 'poorSignal'] as const
type EegAuxSeriesKey = (typeof AUX_EEG_SERIES_KEYS)[number]
type EegLineSeriesKey = EegBandKey | AlgoBpKey | EegAuxSeriesKey

interface EegLineSeriesDefinition {
  readonly key: EegLineSeriesKey
}

interface EegLineSeriesEntry extends EegLineSeriesDefinition {
  readonly label: string
  readonly points: readonly [number, number][]
}

interface SignalPanelEntry {
  readonly key: EegLineSeriesKey
  readonly label: string
  readonly isVisible: boolean
  readonly canToggleVisibility: boolean
  readonly allowLineOptions: boolean
}

const MIN_VIEWPORT_SEC = 0.2
const SIGNAL_BADGE_NONE_COLOR = '#9aa5b1'
const SIGNAL_BADGE_GOOD_COLOR = '#43aa8b'
const SIGNAL_BADGE_FAIR_COLOR = '#f9c74f'
const SIGNAL_BADGE_POOR_COLOR = '#e76f51'
const STORAGE_VISIBLE_SERIES_KEY = 'eeg-line-visible-series'
const ALL_EEG_LINE_SERIES_KEY_SET = new Set<string>([
  ...EEG_BAND_KEYS,
  ...ALGO_BP_KEYS,
  ...AUX_EEG_SERIES_KEYS,
])

const ALL_EEG_LINE_SERIES_KEYS: readonly EegLineSeriesKey[] = [
  ...EEG_BAND_KEYS,
  ...ALGO_BP_KEYS,
  ...AUX_EEG_SERIES_KEYS,
]

const EEG_BAND_KEY_SET = new Set<string>(EEG_BAND_KEYS)

const props = withDefaults(defineProps<{
  readonly data: LogChartDataSnapshot
  readonly windowSec?: number
  readonly dataCorrection?: EegDataCorrection
  readonly calibrationProfile?: EegCalibrationProfile | null
  readonly dataSource?: EegDataSource
  readonly anchorTimestampMs?: number | null
  readonly showSignalBadge?: boolean
  readonly timelineStartTimestampMs?: number | null
  readonly timelineDurationSec?: number | null
  readonly timeViewportStartSec?: number | null
  readonly timeViewportEndSec?: number | null
  readonly uiStateScope?: string
  readonly showSidePanelOpenButton?: boolean
}>(), {
  windowSec: 10,
  dataCorrection: 'raw',
  calibrationProfile: null,
  dataSource: 'bands',
  anchorTimestampMs: null,
  showSignalBadge: true,
  timelineStartTimestampMs: null,
  timelineDurationSec: null,
  timeViewportStartSec: null,
  timeViewportEndSec: null,
  uiStateScope: 'default',
  showSidePanelOpenButton: true,
})

const emit = defineEmits<{
  'update:time-viewport': [viewport: TimeViewportPayload]
}>()

const { t, locale } = useI18n()
const signalStyleStore = useEegSignalStyleStore()
const sidePanelLayoutRef = ref<{
  openPanel?: () => void
  closePanel?: () => void
  isPanelVisible?: () => boolean
} | null>(null)
const chartRoot = ref<HTMLDivElement | null>(null)
const visibleSeriesByKey = reactive<Record<string, boolean>>({})

let chartInstance: ECharts | null = null
let resizeObserver: ResizeObserver | null = null
let suppressDataZoomEmit = false

function isEegBandKey(key: EegLineSeriesKey): key is EegBandKey {
  return EEG_BAND_KEY_SET.has(key)
}

function buildStorageKey(scope: string, key: string): string {
  return `mindwave-eeg-${scope}-${key}`
}

function loadStoredVisibleSeries(scope: string): Record<string, boolean> {
  try {
    const raw = localStorage.getItem(buildStorageKey(scope, STORAGE_VISIBLE_SERIES_KEY))
    if (raw === null) {
      return {}
    }

    const parsed = JSON.parse(raw) as unknown
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return {}
    }

    const result: Record<string, boolean> = {}
    for (const key of ALL_EEG_LINE_SERIES_KEYS) {
      const value = (parsed as Record<string, unknown>)[key]
      if (typeof value === 'boolean') {
        result[key] = value
      }
    }

    return result
  } catch {
    return {}
  }
}

function saveStoredVisibleSeries(scope: string, values: Readonly<Record<string, boolean>>): void {
  try {
    localStorage.setItem(buildStorageKey(scope, STORAGE_VISIBLE_SERIES_KEY), JSON.stringify(values))
  } catch {
    // Ignore localStorage failures.
  }
}

const uiStateScope = computed(() => {
  const rawScope = props.uiStateScope?.trim()
  return rawScope !== undefined && rawScope !== '' ? rawScope : 'default'
})

function applyStoredVisibleSeries(scope: string): void {
  const storedValues = loadStoredVisibleSeries(scope)
  for (const key of ALL_EEG_LINE_SERIES_KEYS) {
    visibleSeriesByKey[key] = storedValues[key] ?? true
  }
}

function toSignalQualityPercent(value: number | null): number | null {
  if (value === null || !Number.isFinite(value)) {
    return null
  }

  const clampedValue = Math.max(0, Math.min(200, value))
  return Math.round((1 - (clampedValue / 200)) * 100)
}

function formatSignalBadgeText(label: string, value: number): string {
  const qualityPercent = toSignalQualityPercent(value)
  if (qualityPercent === null) {
    return label
  }

  return `${label} ${qualityPercent}%`
}

function buildWindowAveragedPoints(
  points: readonly [number, number][],
  windowSec: number,
): readonly [number, number][] {
  if (windowSec === 0 || points.length <= 1) {
    return points
  }

  const windowMs = Math.max(1000, Math.trunc(windowSec) * 1000)
  const averaged: [number, number][] = []
  let sum = 0
  let windowStartIndex = 0

  for (let index = 0; index < points.length; index += 1) {
    const [timestampMs, value] = points[index]
    sum += value

    while (
      windowStartIndex <= index
      && timestampMs - points[windowStartIndex][0] > windowMs
    ) {
      sum -= points[windowStartIndex][1]
      windowStartIndex += 1
    }

    const count = Math.max(1, index - windowStartIndex + 1)
    averaged.push([timestampMs, sum / count])
  }

  return averaged
}

function calibrateBandValue(value: number, key: EegBandKey): number {
  const minValue = props.calibrationProfile?.deviceWideMin[key]
  const maxValue = props.calibrationProfile?.deviceWideMax[key]
  if (
    typeof minValue !== 'number'
    || typeof maxValue !== 'number'
    || !Number.isFinite(minValue)
    || !Number.isFinite(maxValue)
    || maxValue <= minValue
  ) {
    return 0
  }

  const normalized = (value - minValue) / (maxValue - minValue)
  return Math.max(0, Math.min(1, normalized)) * 100
}

function formatSeconds(valueSec: number): string {
  if (!Number.isFinite(valueSec) || valueSec <= 0) {
    return '00:00'
  }

  const totalSeconds = Math.floor(valueSec)
  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60

  if (hours > 0) {
    return [hours, minutes, seconds].map((value) => String(value).padStart(2, '0')).join(':')
  }

  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
}

const effectiveDataCorrection = computed<EegDataCorrection>(() => {
  if (props.dataCorrection !== 'calibrated') {
    return props.dataCorrection
  }

  return props.calibrationProfile?.isComplete === true ? 'calibrated' : 'raw'
})

const sourceSeriesDefinitions = computed<readonly EegLineSeriesDefinition[]>(() => {
  if (props.dataSource === 'algo-bp') {
    return [
      ...ALGO_BP_KEYS.map((key) => ({ key })),
      ...AUX_EEG_SERIES_KEYS.map((key) => ({ key })),
    ]
  }

  return [
    ...EEG_BAND_KEYS.map((key) => ({ key })),
    ...AUX_EEG_SERIES_KEYS.map((key) => ({ key })),
  ]
})

const timelineStartTimestampMs = computed<number>(() => {
  if (typeof props.timelineStartTimestampMs === 'number' && Number.isFinite(props.timelineStartTimestampMs)) {
    return props.timelineStartTimestampMs
  }

  if (typeof props.data.minTimestampMs === 'number' && Number.isFinite(props.data.minTimestampMs)) {
    return props.data.minTimestampMs
  }

  for (const definition of sourceSeriesDefinitions.value) {
    const series = props.data.series.find((item) => item.key === definition.key)
    if (series !== undefined && series.points.length > 0) {
      return series.points[0][0]
    }
  }

  return 0
})

const timelineDurationSec = computed<number | null>(() => {
  if (
    typeof props.timelineDurationSec === 'number'
    && Number.isFinite(props.timelineDurationSec)
    && props.timelineDurationSec > 0
  ) {
    return props.timelineDurationSec
  }

  return null
})

const seriesEntries = computed<readonly EegLineSeriesEntry[]>(() => {
  const baselineTimestampMs = timelineStartTimestampMs.value
  const boundedDurationSec = timelineDurationSec.value
  const normalizedWindowSec = props.windowSec === 0 ? 0 : Math.max(1, Math.trunc(props.windowSec))

  return sourceSeriesDefinitions.value.map((definition) => {
    const sourceSeries = props.data.series.find((item) => item.key === definition.key)
    const averagedPoints = buildWindowAveragedPoints(
      (sourceSeries?.points ?? []) as readonly [number, number][],
      normalizedWindowSec,
    )

    const chartPoints: [number, number][] = []
    for (const [timestampMs, sourceValue] of averagedPoints) {
      const relativeSec = (timestampMs - baselineTimestampMs) / 1000
      if (!Number.isFinite(relativeSec)) {
        continue
      }

      if (boundedDurationSec !== null && (relativeSec < 0 || relativeSec > boundedDurationSec)) {
        continue
      }

      let value = sourceValue
      if (effectiveDataCorrection.value === 'calibrated' && isEegBandKey(definition.key)) {
        value = calibrateBandValue(sourceValue, definition.key)
      }

      chartPoints.push([relativeSec, value])
    }

    return {
      key: definition.key,
      label: t(`monitoring.series.${definition.key}`),
      points: chartPoints,
    }
  })
})

const lineStyleToken = computed(() => {
  return sourceSeriesDefinitions.value
    .map((definition) => {
      const style = signalStyleStore.getSignalStyle(definition.key)
      return `${definition.key}:${style.color}:${style.lineType}:${style.glowIntensity}`
    })
    .join('|')
})

watch(seriesEntries, (entries) => {
  for (const entry of entries) {
    if (visibleSeriesByKey[entry.key] === undefined) {
      visibleSeriesByKey[entry.key] = true
    }
  }
}, { immediate: true })

const visibilityPersistenceToken = computed(() => {
  return ALL_EEG_LINE_SERIES_KEYS
    .map((key) => `${key}:${visibleSeriesByKey[key] !== false ? '1' : '0'}`)
    .join('|')
})

watch(uiStateScope, (scope) => {
  applyStoredVisibleSeries(scope)
  renderChart()
}, { immediate: true })

watch([uiStateScope, visibilityPersistenceToken], ([scope]) => {
  const valuesToStore = Object.fromEntries(
    ALL_EEG_LINE_SERIES_KEYS.map((key) => [key, visibleSeriesByKey[key] !== false]),
  ) as Record<string, boolean>
  saveStoredVisibleSeries(scope, valuesToStore)
})

const visibleSignalsCount = computed(() => {
  return seriesEntries.value.reduce((count, entry) => {
    return count + (visibleSeriesByKey[entry.key] !== false ? 1 : 0)
  }, 0)
})

const signalsSubtitleText = computed(() => {
  return t('monitoring.eegLine.signalsSubtitle', {
    visible: visibleSignalsCount.value,
    total: seriesEntries.value.length,
  })
})

const signalPanelEntries = computed<readonly SignalPanelEntry[]>(() => {
  return seriesEntries.value.map((entry) => ({
    key: entry.key,
    label: entry.label,
    isVisible: visibleSeriesByKey[entry.key] !== false,
    canToggleVisibility: true,
    allowLineOptions: true,
  }))
})

const poorSignalValue = computed(() => {
  return getLatestSeriesValue(props.data, 'poorSignal', props.anchorTimestampMs)
})

const signalBadgeText = computed(() => {
  const value = poorSignalValue.value

  if (value === null) return t('monitoring.badge.signalNone')
  if (value === 0) return formatSignalBadgeText(t('monitoring.badge.signalGood'), value)
  if (value <= 25) return formatSignalBadgeText(t('monitoring.badge.signalFair'), value)
  return formatSignalBadgeText(t('monitoring.badge.signalPoor'), value)
})

const signalBadgeColor = computed(() => {
  const value = poorSignalValue.value

  if (value === null) return SIGNAL_BADGE_NONE_COLOR
  if (value === 0) return SIGNAL_BADGE_GOOD_COLOR
  if (value <= 25) return SIGNAL_BADGE_FAIR_COLOR
  return SIGNAL_BADGE_POOR_COLOR
})

const xAxisRange = computed(() => {
  const boundedDurationSec = timelineDurationSec.value
  if (boundedDurationSec !== null) {
    return {
      min: 0,
      max: Math.max(boundedDurationSec, MIN_VIEWPORT_SEC),
    }
  }

  let minSec = Number.POSITIVE_INFINITY
  let maxSec = Number.NEGATIVE_INFINITY

  for (const entry of seriesEntries.value) {
    for (const [timeSec] of entry.points) {
      minSec = Math.min(minSec, timeSec)
      maxSec = Math.max(maxSec, timeSec)
    }
  }

  if (!Number.isFinite(minSec) || !Number.isFinite(maxSec)) {
    return {
      min: 0,
      max: 60,
    }
  }

  if (maxSec <= minSec) {
    return {
      min: minSec,
      max: minSec + MIN_VIEWPORT_SEC,
    }
  }

  return {
    min: minSec,
    max: maxSec,
  }
})

function normalizeViewport(startSec: number, endSec: number): TimeViewportPayload {
  const minimum = xAxisRange.value.min
  const maximum = xAxisRange.value.max
  const maxStart = Math.max(minimum, maximum - MIN_VIEWPORT_SEC)
  const clampedStart = Math.max(minimum, Math.min(startSec, maxStart))
  const clampedEnd = Math.min(
    Math.max(endSec, clampedStart + MIN_VIEWPORT_SEC),
    maximum,
  )

  return {
    startSec: clampedStart,
    endSec: clampedEnd,
  }
}

const externalViewport = computed<TimeViewportPayload | null>(() => {
  if (
    typeof props.timeViewportStartSec !== 'number'
    || typeof props.timeViewportEndSec !== 'number'
    || !Number.isFinite(props.timeViewportStartSec)
    || !Number.isFinite(props.timeViewportEndSec)
  ) {
    return null
  }

  return normalizeViewport(props.timeViewportStartSec, props.timeViewportEndSec)
})

function setAllSignalsVisible(isVisible: boolean): void {
  for (const entry of seriesEntries.value) {
    visibleSeriesByKey[entry.key] = isVisible
  }

  renderChart()
}

function handleSignalPanelVisibilityToggle(payload: { key: string, isVisible: boolean }): void {
  if (!ALL_EEG_LINE_SERIES_KEY_SET.has(payload.key)) {
    return
  }

  handleSeriesVisibilityChange(payload.key as EegLineSeriesKey, payload.isVisible)
}

function handleSeriesVisibilityChange(key: EegLineSeriesKey, value: unknown): void {
  visibleSeriesByKey[key] = value !== false
  renderChart()
}

function resolveLineType(lineType: EegSignalLineType): number[] | 'solid' | 'dashed' | 'dotted' {
  switch (lineType) {
    case 'solid':
      return 'solid'
    case 'dashed':
      return 'dashed'
    case 'dotted':
      return 'dotted'
    case 'twodash':
      return [8, 5, 8, 12]
    case 'longdash':
      return [22, 8]
    case 'dotdash':
      return [2, 6, 14, 8]
    default:
      return 'solid'
  }
}

function buildChartOption() {
  const visibleEntries = seriesEntries.value.filter((entry) => visibleSeriesByKey[entry.key] !== false)
  const range = xAxisRange.value
  const viewport = externalViewport.value ?? {
    startSec: range.min,
    endSec: range.max,
  }

  const isPercentScale = effectiveDataCorrection.value === 'calibrated' && props.dataSource === 'bands'

  return {
    animation: false,
    backgroundColor: 'transparent',
    grid: {
      left: 64,
      right: 28,
      top: 36,
      bottom: 58,
      containLabel: true,
    },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'cross' },
      formatter: (params: Array<{ marker?: string, seriesName?: string, value?: number[] }>) => {
        if (params.length === 0) {
          return ''
        }

        const firstValue = params[0]?.value
        const timeSec = Array.isArray(firstValue) && typeof firstValue[0] === 'number' ? firstValue[0] : 0
        const lines = [`<strong>${formatSeconds(timeSec)}</strong>`]

        for (const param of params) {
          const numericValue = Array.isArray(param.value) && typeof param.value[1] === 'number'
            ? param.value[1]
            : 0

          const formattedValue = isPercentScale
            ? `${numericValue.toFixed(1)}%`
            : numericValue.toFixed(2)

          lines.push(`${param.marker ?? ''}${param.seriesName ?? ''}: ${formattedValue}`)
        }

        return lines.join('<br>')
      },
    },
    xAxis: {
      type: 'value',
      min: range.min,
      max: range.max,
      name: t('monitoring.axis.time'),
      nameLocation: 'middle',
      nameGap: 34,
      axisLine: { lineStyle: { color: 'rgba(255, 255, 255, 0.22)' } },
      axisLabel: {
        color: 'rgba(255, 255, 255, 0.72)',
        formatter: (value: number) => formatSeconds(value),
      },
      splitLine: { lineStyle: { color: 'rgba(255, 255, 255, 0.1)' } },
    },
    yAxis: {
      type: 'value',
      name: isPercentScale
        ? t('monitoring.axis.eegCalibrated')
        : t('monitoring.axis.eegPower'),
      min: isPercentScale ? 0 : undefined,
      max: isPercentScale ? 100 : undefined,
      nameTextStyle: { color: 'rgba(255, 255, 255, 0.72)' },
      axisLine: { show: false },
      axisLabel: {
        color: 'rgba(255, 255, 255, 0.72)',
        formatter: isPercentScale ? '{value}%' : '{value}',
      },
      splitLine: { lineStyle: { color: 'rgba(255, 255, 255, 0.1)' } },
    },
    dataZoom: [
      {
        type: 'inside',
        xAxisIndex: [0],
        filterMode: 'none',
        startValue: viewport.startSec,
        endValue: viewport.endSec,
      },
      {
        type: 'slider',
        xAxisIndex: [0],
        filterMode: 'none',
        bottom: 6,
        height: 18,
        startValue: viewport.startSec,
        endValue: viewport.endSec,
      },
    ],
    series: visibleEntries.map((entry) => {
      const style = signalStyleStore.getSignalStyle(entry.key)
      return {
        name: entry.label,
        type: 'line' as const,
        data: entry.points,
        showSymbol: false,
        connectNulls: false,
        sampling: 'lttb',
        animation: false,
        lineStyle: {
          color: style.color,
          width: 1.9,
          type: resolveLineType(style.lineType),
          shadowBlur: style.glowIntensity,
          shadowColor: style.glowIntensity > 0 ? style.color : 'transparent',
        },
        itemStyle: {
          color: style.color,
          shadowBlur: style.glowIntensity,
          shadowColor: style.glowIntensity > 0 ? style.color : 'transparent',
        },
      }
    }),
  }
}

function extractViewportFromZoomEvent(event: unknown): TimeViewportPayload | null {
  const payload = event as {
    readonly batch?: ReadonlyArray<{ readonly startValue?: number, readonly endValue?: number }>
    readonly startValue?: number
    readonly endValue?: number
  }

  const candidates = Array.isArray(payload.batch)
    ? payload.batch
    : [payload]

  for (const candidate of candidates) {
    if (
      typeof candidate.startValue === 'number'
      && typeof candidate.endValue === 'number'
      && Number.isFinite(candidate.startValue)
      && Number.isFinite(candidate.endValue)
    ) {
      return normalizeViewport(candidate.startValue, candidate.endValue)
    }
  }

  if (chartInstance === null) {
    return null
  }

  const option = chartInstance.getOption() as {
    readonly dataZoom?: ReadonlyArray<{ readonly startValue?: number, readonly endValue?: number }>
  }
  const firstDataZoom = option.dataZoom?.[0]

  if (
    firstDataZoom !== undefined
    && typeof firstDataZoom.startValue === 'number'
    && typeof firstDataZoom.endValue === 'number'
    && Number.isFinite(firstDataZoom.startValue)
    && Number.isFinite(firstDataZoom.endValue)
  ) {
    return normalizeViewport(firstDataZoom.startValue, firstDataZoom.endValue)
  }

  return null
}

function handleDataZoom(event: unknown): void {
  if (suppressDataZoomEmit) {
    return
  }

  const viewport = extractViewportFromZoomEvent(event)
  if (viewport === null) {
    return
  }

  emit('update:time-viewport', viewport)
}

function renderChart(): void {
  if (chartInstance === null) {
    return
  }

  suppressDataZoomEmit = true
  chartInstance.setOption(buildChartOption(), {
    notMerge: false,
    lazyUpdate: true,
    replaceMerge: ['grid', 'xAxis', 'yAxis', 'dataZoom', 'series'],
  })

  queueMicrotask(() => {
    suppressDataZoomEmit = false
  })
}

onMounted(() => {
  if (chartRoot.value === null) {
    return
  }

  chartInstance = init(chartRoot.value, undefined, { renderer: 'canvas' })
  chartInstance.on('datazoom', handleDataZoom)
  renderChart()

  resizeObserver = new ResizeObserver(() => {
    chartInstance?.resize()
  })
  resizeObserver.observe(chartRoot.value)
})

watch([
  () => props.data,
  () => props.windowSec,
  () => props.dataCorrection,
  () => props.calibrationProfile,
  () => props.dataSource,
  () => props.anchorTimestampMs,
  () => props.timelineStartTimestampMs,
  () => props.timelineDurationSec,
  () => props.timeViewportStartSec,
  () => props.timeViewportEndSec,
  () => locale.value,
  lineStyleToken,
  seriesEntries,
  xAxisRange,
  externalViewport,
], () => {
  renderChart()
}, { deep: true })

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  resizeObserver = null

  if (chartInstance !== null) {
    chartInstance.off('datazoom', handleDataZoom)
    chartInstance.dispose()
    chartInstance = null
  }
})

function openSidePanel(): void {
  sidePanelLayoutRef.value?.openPanel?.()
}

function closeSidePanel(): void {
  sidePanelLayoutRef.value?.closePanel?.()
}

function isSidePanelVisible(): boolean {
  return sidePanelLayoutRef.value?.isPanelVisible?.() === true
}

defineExpose({
  openSidePanel,
  closeSidePanel,
  isSidePanelVisible,
})
</script>

<style scoped>
.eeg-line-timeline-chart__canvas {
  width: 100%;
  height: 100%;
  min-height: 320px;
}

.eeg-line-timeline-chart__badge {
  font-size: 11px;
  background: rgba(0, 0, 0, 0.35);
  padding: 2px 8px;
  border-radius: 4px;
  pointer-events: none;
  z-index: 1;
}
</style>
