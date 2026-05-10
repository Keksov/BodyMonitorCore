<template>
  <div class="eeg-current-readings-chart" :class="{ 'eeg-current-readings-chart--compact': compact }">
    <div ref="chartRoot" class="eeg-current-readings-chart__canvas" />

    <div
      v-if="showSignalBadge && signalBadgeText"
      class="eeg-current-readings-chart__badge"
      :style="{ color: signalBadgeColor }"
    >
      {{ signalBadgeText }}
    </div>

    <div v-if="showStateHint && stateHintText !== null" class="eeg-current-readings-chart__state-hint">
      {{ stateHintText }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watchEffect } from 'vue'
import { useI18n } from 'vue-i18n'
import { use, init, type ECharts } from 'echarts/core'
import { BarChart } from 'echarts/charts'
import { GridComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot } from '@protocol'
import type { EegCalibrationProfile } from '../stores/device'
import type { EegBandScaleMode } from '../stores/preferences'
import {
  EEG_BAND_KEYS,
  type EegBandKey,
  buildEegBandAveragesSnapshot,
  calibrateBandValues,
  getLatestSeriesValue,
  normalizeBandDistribution,
} from '../services/eeg-band-snapshot'
import { EEG_BAND_COLORS } from '../services/eeg-band-colors'

use([BarChart, GridComponent, TooltipComponent, CanvasRenderer])

const props = withDefaults(defineProps<{
  readonly data: LogChartDataSnapshot | null
  readonly windowSec?: number
  readonly scaleMode?: EegBandScaleMode
  readonly calibrationProfile?: EegCalibrationProfile | null
  readonly anchorTimestampMs?: number | null
  readonly compact?: boolean
  readonly showSignalBadge?: boolean
  readonly showStateHint?: boolean
  readonly forceNoSignal?: boolean
  readonly emptyHintText?: string | null
}>(), {
  windowSec: 1,
  scaleMode: 'normalized',
  calibrationProfile: null,
  anchorTimestampMs: null,
  compact: false,
  showSignalBadge: false,
  showStateHint: true,
  forceNoSignal: false,
  emptyHintText: null,
})

const { t } = useI18n()

const chartRoot = ref<HTMLDivElement | null>(null)
let chartInstance: ECharts | null = null
let resizeObserver: ResizeObserver | null = null

const BAND_FREQ: Record<EegBandKey, string> = {
  delta: '0.5–4 Hz',
  theta: '4–8 Hz',
  alpha1: '8–10 Hz',
  alpha2: '10–13 Hz',
  beta1: '13–17 Hz',
  beta2: '17–30 Hz',
  gamma1: '30–40 Hz',
  gamma2: '40–100 Hz',
}

const normalizedValueFormatter = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
})

const absoluteValueFormatter = new Intl.NumberFormat(undefined, {
  maximumFractionDigits: 2,
  notation: 'compact',
})

const effectiveScaleMode = computed<EegBandScaleMode>(() => {
  if (props.scaleMode !== 'calibrated') {
    return props.scaleMode
  }

  return props.calibrationProfile?.isComplete === true ? 'calibrated' : 'raw'
})

const chartSnapshot = computed(() => {
  if (props.data === null) {
    return null
  }

  const bandSnapshot = buildEegBandAveragesSnapshot(
    props.data,
    props.windowSec,
    props.anchorTimestampMs,
  )
  if (bandSnapshot === null) {
    return null
  }

  const rawBandValues = bandSnapshot.bandValues
  let bandValues = rawBandValues

  if (effectiveScaleMode.value === 'normalized') {
    bandValues = normalizeBandDistribution(rawBandValues)
  }

  if (effectiveScaleMode.value === 'calibrated' && props.calibrationProfile?.isComplete === true) {
    bandValues = calibrateBandValues(
      rawBandValues,
      props.calibrationProfile.deviceWideMin,
      props.calibrationProfile.deviceWideMax,
    )
  }

  return {
    ...bandSnapshot,
    bandValues,
  }
})

const poorSignalValue = computed(() => {
  if (props.data === null) {
    return null
  }

  return getLatestSeriesValue(props.data, 'poorSignal', props.anchorTimestampMs)
})

const hasAnySamples = computed(() => {
  const snapshot = chartSnapshot.value
  if (snapshot === null) {
    return false
  }

  return EEG_BAND_KEYS.some((bandKey) => snapshot.sampleCounts[bandKey] > 0)
})

const signalBadgeText = computed(() => {
  if (props.forceNoSignal) {
    return t('monitoring.badge.signalNone')
  }

  const value = poorSignalValue.value

  if (value === null) return t('monitoring.badge.signalNone')
  if (value === 0) return t('monitoring.badge.signalGood')
  if (value <= 25) return t('monitoring.badge.signalFair')
  return t('monitoring.badge.signalPoor')
})

const signalBadgeColor = computed(() => {
  if (props.forceNoSignal) {
    return '#9aa5b1'
  }

  const value = poorSignalValue.value

  if (value === null) return '#9aa5b1'
  if (value === 0) return '#43aa8b'
  if (value <= 25) return '#f9c74f'
  return '#e76f51'
})

const stateHintText = computed(() => {
  if (props.forceNoSignal) {
    return t('monitoring.badge.signalNone')
  }

  if (!hasAnySamples.value) {
    return props.emptyHintText ?? t('monitoring.chartEmptyTitle')
  }

  const poorSignal = poorSignalValue.value
  if (poorSignal === null) {
    return t('monitoring.badge.signalNone')
  }

  if (poorSignal > 25) {
    return t('monitoring.badge.signalPoor')
  }

  if (poorSignal > 0) {
    return t('monitoring.badge.signalFair')
  }

  return null
})

function formatBandValue(value: number): string {
  if (effectiveScaleMode.value === 'normalized' || effectiveScaleMode.value === 'calibrated') {
    return `${normalizedValueFormatter.format(value)}%`
  }

  return absoluteValueFormatter.format(value)
}

function buildOption() {
  const snapshot = chartSnapshot.value
  const isPercentScale = effectiveScaleMode.value === 'normalized' || effectiveScaleMode.value === 'calibrated'
  const labelFontSize = props.compact ? 10 : 11
  const freqFontSize = props.compact ? 9 : 10
  const categories = EEG_BAND_KEYS.map((key) => ({
    value: key,
    textStyle: {},
  }))

  return {
    animation: false,
    backgroundColor: 'transparent',
    grid: {
      left: props.compact ? 40 : 54,
      right: props.compact ? 16 : 20,
      top: props.showSignalBadge ? (props.compact ? 34 : 40) : (props.compact ? 18 : 24),
      bottom: props.compact ? 48 : 58,
      containLabel: true,
    },
    tooltip: {
      trigger: 'item',
      formatter: (param: { name?: string, value?: number | number[] }) => {
        const rawValue = Array.isArray(param.value) ? param.value.at(-1) : param.value
        const numericValue = typeof rawValue === 'number' ? rawValue : 0
        return `<strong>${t(`monitoring.series.${param.name ?? ''}`)}</strong><br>${formatBandValue(numericValue)}`
      },
    },
    xAxis: {
      type: 'category',
      data: categories,
      axisTick: { alignWithLabel: true },
      axisLine: { lineStyle: { color: 'rgba(255, 255, 255, 0.18)' } },
      axisLabel: {
        interval: 0,
        formatter: (key: string) => {
          const name = t(`monitoring.series.${key}`)
          const freq = BAND_FREQ[key as EegBandKey] ?? ''
          return `{name|${name}}\n{freq|${freq}}`
        },
        rich: {
          name: {
            color: 'rgba(255, 255, 255, 0.72)',
            fontSize: labelFontSize,
            lineHeight: labelFontSize + 4,
          },
          freq: {
            color: 'rgba(255, 255, 255, 0.40)',
            fontSize: freqFontSize,
            lineHeight: freqFontSize + 3,
          },
        },
      },
    },
    yAxis: {
      type: 'value',
      min: 0,
      max: isPercentScale ? 100 : undefined,
      name: props.compact
        ? ''
        : (isPercentScale
          ? (effectiveScaleMode.value === 'calibrated' ? t('monitoring.axis.eegCalibrated') : t('monitoring.axis.eegPct'))
          : t('monitoring.axis.eegPower')),
      nameTextStyle: { color: 'rgba(255, 255, 255, 0.7)' },
      splitLine: { lineStyle: { color: 'rgba(255, 255, 255, 0.1)' } },
      axisLabel: {
        color: 'rgba(255, 255, 255, 0.68)',
        formatter: isPercentScale ? '{value}%' : '{value}',
        fontSize: props.compact ? 10 : 11,
      },
    },
    series: [
      {
        type: 'bar' as const,
        data: EEG_BAND_KEYS.map((key) => ({
          value: props.forceNoSignal ? 0 : (snapshot?.bandValues[key] ?? 0),
          itemStyle: {
            color: EEG_BAND_COLORS[key],
            borderRadius: [6, 6, 0, 0],
          },
        })),
        barMaxWidth: props.compact ? 24 : 42,
      },
    ],
  }
}

function renderChart() {
  if (chartInstance === null) {
    return
  }

  chartInstance.setOption(buildOption(), {
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

watchEffect(() => {
  chartSnapshot.value
  poorSignalValue.value
  props.compact
  props.scaleMode
  effectiveScaleMode.value
  props.calibrationProfile
  props.showSignalBadge
  props.windowSec
  props.anchorTimestampMs
  props.forceNoSignal
  t('monitoring.axis.eegPower')
  renderChart()
})

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  resizeObserver = null
  chartInstance?.dispose()
  chartInstance = null
})
</script>

<style scoped>
.eeg-current-readings-chart {
  position: relative;
  width: 100%;
  height: 100%;
  min-height: 220px;
}

.eeg-current-readings-chart--compact {
  min-height: 160px;
}

.eeg-current-readings-chart__canvas {
  width: 100%;
  height: 100%;
  min-height: 220px;
}

.eeg-current-readings-chart--compact .eeg-current-readings-chart__canvas {
  min-height: 160px;
}

.eeg-current-readings-chart__badge {
  position: absolute;
  top: 8px;
  right: 10px;
  font-size: 11px;
  background: rgba(0, 0, 0, 0.35);
  padding: 2px 8px;
  border-radius: 4px;
  pointer-events: none;
  z-index: 2;
}

.eeg-current-readings-chart__state-hint {
  position: absolute;
  left: 10px;
  bottom: 8px;
  font-size: 11px;
  color: rgba(255, 255, 255, 0.72);
  background: rgba(0, 0, 0, 0.38);
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: 4px;
  padding: 2px 8px;
  pointer-events: none;
  z-index: 2;
}

.eeg-current-readings-chart--compact .eeg-current-readings-chart__state-hint,
.eeg-current-readings-chart--compact .eeg-current-readings-chart__badge {
  font-size: 10px;
}
</style>
