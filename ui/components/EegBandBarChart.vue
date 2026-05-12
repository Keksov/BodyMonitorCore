<template>
  <div class="eeg-band-bar-chart" ref="chartRoot">
    <div v-if="signalBadgeText" class="eeg-band-bar-chart__badge" :style="{ color: signalBadgeColor }">
      {{ signalBadgeText }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { use, init, type ECharts } from 'echarts/core'
import { BarChart, LineChart } from 'echarts/charts'
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot, LogChartSeriesKey } from '@protocol'
import type { EegCalibrationProfile } from '../stores/device'
import type { EegBandScaleMode } from '../stores/preferences'
import {
  EEG_BAND_KEYS,
  type EegBandKey,
  buildEegBandAveragesSnapshot,
  calibrateBandValues,
  normalizeBandDistribution,
} from '../services/eeg-band-snapshot'
import { EEG_BAND_COLORS } from '../services/eeg-band-colors'

use([BarChart, LineChart, GridComponent, LegendComponent, TooltipComponent, CanvasRenderer])

const props = withDefaults(defineProps<{
  readonly data: LogChartDataSnapshot
  readonly windowSec: number
  readonly scaleMode: EegBandScaleMode
  readonly calibrationProfile?: EegCalibrationProfile | null
  readonly anchorTimestampMs?: number | null
}>(), {
  calibrationProfile: null,
  anchorTimestampMs: null,
})

const { t } = useI18n()
const chartRoot = ref<HTMLDivElement | null>(null)
let chartInstance: ECharts | null = null
let resizeObserver: ResizeObserver | null = null

const normalizedValueFormatter = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
})

const absoluteValueFormatter = new Intl.NumberFormat(undefined, {
  maximumFractionDigits: 2,
  notation: 'compact',
})

const scoreValueFormatter = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
})

function getSeriesPoints(key: LogChartSeriesKey): readonly [number, number][] {
  const item = props.data.series.find((series) => series.key === key)
  return (item?.points ?? []) as readonly [number, number][]
}

function averageWindow(points: readonly [number, number][], startTimestampMs: number, endTimestampMs: number): number {
  const windowPoints = points.filter((point) => point[0] >= startTimestampMs && point[0] <= endTimestampMs)
  if (windowPoints.length === 0) {
    return 0
  }

  return windowPoints.reduce((sum, point) => sum + point[1], 0) / windowPoints.length
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

const chartSnapshot = computed(() => {
  const bandSnapshot = buildEegBandAveragesSnapshot(
    props.data,
    props.windowSec,
    props.anchorTimestampMs,
  )
  if (bandSnapshot === null) {
    return null
  }

  const anchorTimestampMs = bandSnapshot.anchorTimestampMs
  const clampedWindowSec = Math.max(1, Math.trunc(props.windowSec))
  const windowStartMs = anchorTimestampMs - clampedWindowSec * 1000
  const rawBandValues = bandSnapshot.bandValues

  let bandValues = rawBandValues
  if (props.scaleMode === 'normalized') {
    bandValues = normalizeBandDistribution(rawBandValues)
  }

  if (props.scaleMode === 'calibrated' && props.calibrationProfile?.isComplete === true) {
    bandValues = calibrateBandValues(
      rawBandValues,
      props.calibrationProfile.deviceWideMin,
      props.calibrationProfile.deviceWideMax,
    )
  }

  return {
    bandValues,
    attention: Math.min(100, averageWindow(getSeriesPoints('attention'), windowStartMs, anchorTimestampMs)),
    meditation: Math.min(100, averageWindow(getSeriesPoints('meditation'), windowStartMs, anchorTimestampMs)),
  }
})

const signalBadgeText = computed(() => {
  const points = getSeriesPoints('poorSignal')
  const value = points.at(-1)?.[1] ?? null

  if (value === null) return t('monitoring.badge.signalNone')
  if (value === 0) return formatSignalBadgeText(t('monitoring.badge.signalGood'), value)
  if (value <= 25) return formatSignalBadgeText(t('monitoring.badge.signalFair'), value)
  return formatSignalBadgeText(t('monitoring.badge.signalPoor'), value)
})

const signalBadgeColor = computed(() => {
  const points = getSeriesPoints('poorSignal')
  const value = points.at(-1)?.[1] ?? null

  if (value === null) return '#9aa5b1'
  if (value === 0) return '#43aa8b'
  if (value <= 25) return '#f9c74f'
  return '#e76f51'
})

function formatBandValue(value: number): string {
  if (props.scaleMode === 'normalized' || props.scaleMode === 'calibrated') {
    return `${normalizedValueFormatter.format(value)}%`
  }

  return absoluteValueFormatter.format(value)
}

function formatScoreValue(value: number): string {
  return `${scoreValueFormatter.format(value)}%`
}

function buildOption() {
  const snapshot = chartSnapshot.value
  const isPercentScale = props.scaleMode === 'normalized' || props.scaleMode === 'calibrated'
  const categories = EEG_BAND_KEYS.map((key) => t(`monitoring.series.${key}`))
  const bandSeriesData = EEG_BAND_KEYS.map((key) => ({
    value: snapshot?.bandValues[key] ?? 0,
    itemStyle: { color: EEG_BAND_COLORS[key] },
  }))
  const attentionValue = snapshot?.attention ?? 0
  const meditationValue = snapshot?.meditation ?? 0

  return {
    animation: false,
    backgroundColor: 'transparent',
    grid: {
      left: 56,
      right: 60,
      top: 44,
      bottom: 48,
      containLabel: true,
    },
    legend: {
      top: 8,
      textStyle: { color: 'rgba(255, 255, 255, 0.68)' },
    },
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: 'shadow' },
      formatter: (params: Array<{
        axisValueLabel?: string
        seriesName?: string
        value?: number | number[]
      }>) => {
        if (params.length === 0) {
          return ''
        }

        const lines = [`<strong>${params[0]?.axisValueLabel ?? ''}</strong>`]
        for (const param of params) {
          const rawValue = Array.isArray(param.value) ? param.value.at(-1) : param.value
          const numericValue = typeof rawValue === 'number' ? rawValue : 0
          const formattedValue = param.seriesName === t('monitoring.axis.eegBands')
            ? formatBandValue(numericValue)
            : formatScoreValue(numericValue)
          lines.push(`${param.seriesName ?? ''}: ${formattedValue}`)
        }

        return lines.join('<br>')
      },
    },
    xAxis: {
      type: 'category',
      data: categories,
      axisTick: { alignWithLabel: true },
      axisLine: { lineStyle: { color: 'rgba(255, 255, 255, 0.18)' } },
      axisLabel: { color: 'rgba(255, 255, 255, 0.72)' },
    },
    yAxis: [
      {
        type: 'value',
        name: isPercentScale
          ? (props.scaleMode === 'calibrated' ? t('monitoring.axis.eegCalibrated') : t('monitoring.axis.eegPct'))
          : t('monitoring.axis.eegPower'),
        min: 0,
        max: isPercentScale ? 100 : undefined,
        nameTextStyle: { color: 'rgba(255, 255, 255, 0.72)' },
        axisLine: { show: false },
        splitLine: { lineStyle: { color: 'rgba(255, 255, 255, 0.1)' } },
        axisLabel: {
          color: 'rgba(255, 255, 255, 0.68)',
          formatter: isPercentScale ? '{value}%' : '{value}',
        },
      },
      {
        type: 'value',
        name: t('monitoring.axis.eegScore'),
        min: 0,
        max: 100,
        position: 'right',
        nameTextStyle: { color: 'rgba(255, 255, 255, 0.72)' },
        splitLine: { show: false },
        axisLabel: {
          color: 'rgba(255, 255, 255, 0.68)',
          formatter: '{value}%'
        },
      },
    ],
    series: [
      {
        name: t('monitoring.axis.eegBands'),
        type: 'bar' as const,
        barMaxWidth: 42,
        data: bandSeriesData,
        itemStyle: {
          borderRadius: [6, 6, 0, 0],
        },
      },
      {
        name: t('monitoring.series.attention'),
        type: 'line' as const,
        yAxisIndex: 1,
        smooth: false,
        showSymbol: false,
        lineStyle: { width: 2, type: 'dashed', color: '#f4a261' },
        itemStyle: { color: '#f4a261' },
        data: EEG_BAND_KEYS.map(() => attentionValue),
      },
      {
        name: t('monitoring.series.meditation'),
        type: 'line' as const,
        yAxisIndex: 1,
        smooth: false,
        showSymbol: false,
        lineStyle: { width: 2, type: 'dashed', color: '#8ecae6' },
        itemStyle: { color: '#8ecae6' },
        data: EEG_BAND_KEYS.map(() => meditationValue),
      },
    ],
  }
}

function renderChart() {
  chartInstance?.setOption(buildOption(), {
    notMerge: false,
    lazyUpdate: true,
    replaceMerge: ['series', 'xAxis', 'yAxis'],
  })
}

onMounted(() => {
  if (chartRoot.value === null) {
    return
  }

  chartInstance = init(chartRoot.value, undefined, { renderer: 'canvas' })
  renderChart()

  resizeObserver = new ResizeObserver(() => {
    chartInstance?.resize()
  })
  resizeObserver.observe(chartRoot.value)
})

watch([
  () => props.data,
  () => props.windowSec,
  () => props.scaleMode,
  () => props.calibrationProfile,
  () => props.anchorTimestampMs,
], renderChart)

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  resizeObserver = null
  chartInstance?.dispose()
  chartInstance = null
})
</script>

<style scoped>
.eeg-band-bar-chart {
  position: relative;
  width: 100%;
  height: 100%;
  min-height: 320px;
}

.eeg-band-bar-chart__badge {
  position: absolute;
  top: 8px;
  right: 12px;
  font-size: 11px;
  background: rgba(0, 0, 0, 0.35);
  padding: 2px 8px;
  border-radius: 4px;
  pointer-events: none;
  z-index: 1;
}
</style>