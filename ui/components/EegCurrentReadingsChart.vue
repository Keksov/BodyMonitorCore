<template>
  <eeg-chart-side-panel-layout
    ref="sidePanelLayoutRef"
    :ui-state-scope="resolvedUiStateScope"
    storage-key="eeg-shared-side-panel-visible"
    :panel-title="t('monitoring.eegLine.signalsTitle')"
    :panel-aria-label="t('monitoring.eegLine.signalsTitle')"
    :open-button-label="t('monitoring.eegLine.openPanel')"
    :close-button-label="t('monitoring.eegLine.closePanel')"
    :show-open-button="showSidePanelOpenButton"
  >
    <div class="eeg-current-readings-chart" :class="{ 'eeg-current-readings-chart--compact': compact }">
      <div ref="chartRoot" class="eeg-current-readings-chart__canvas" />

      <div v-if="showStateHint && stateHintText !== null" class="eeg-current-readings-chart__state-hint">
        {{ stateHintText }}
      </div>
    </div>

    <template #overlay>
      <div
        v-if="showSignalBadge && signalBadgeText"
        class="eeg-current-readings-chart__badge"
        :style="{ color: signalBadgeColor }"
      >
        {{ signalBadgeText }}
      </div>
    </template>

    <template #panelBody>
      <eeg-signal-style-list-panel :entries="signalPanelEntries" />
    </template>
  </eeg-chart-side-panel-layout>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watchEffect } from 'vue'
import { useI18n } from 'vue-i18n'
import { use, init, type ECharts } from 'echarts/core'
import { BarChart } from 'echarts/charts'
import { GridComponent, TooltipComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot } from '@protocol'
import EegChartSidePanelLayout from './EegChartSidePanelLayout.vue'
import EegSignalStyleListPanel from './EegSignalStyleListPanel.vue'
import type { EegCalibrationProfile } from '../stores/device'
import type { EegDataCorrection, EegDataSource } from '../stores/preferences'
import { useEegSignalStyleStore } from '../stores/eeg-signal-style'
import {
  ALGO_BP_KEYS,
  EEG_BAND_KEYS,
  type AlgoBpKey,
  type EegBandKey,
  buildAlgoBpSnapshot,
  buildEegBandAveragesSnapshot,
  calibrateBandValues,
  getLatestSeriesValue,
} from '../services/eeg-band-snapshot'

use([BarChart, GridComponent, TooltipComponent, CanvasRenderer])

const props = withDefaults(defineProps<{
  readonly data: LogChartDataSnapshot | null
  readonly windowSec?: number
  readonly dataCorrection?: EegDataCorrection
  readonly calibrationProfile?: EegCalibrationProfile | null
  readonly anchorTimestampMs?: number | null
  readonly compact?: boolean
  readonly showSignalBadge?: boolean
  readonly showStateHint?: boolean
  readonly forceNoSignal?: boolean
  readonly emptyHintText?: string | null
  readonly dataSource?: EegDataSource
  readonly uiStateScope?: string | null
  readonly showSidePanelOpenButton?: boolean
}>(), {
  windowSec: 1,
  dataCorrection: 'raw',
  calibrationProfile: null,
  anchorTimestampMs: null,
  compact: false,
  showSignalBadge: false,
  showStateHint: true,
  forceNoSignal: false,
  emptyHintText: null,
  dataSource: 'bands',
  uiStateScope: null,
  showSidePanelOpenButton: true,
})

const { t } = useI18n()
const signalStyleStore = useEegSignalStyleStore()

const sidePanelLayoutRef = ref<{
  openPanel?: () => void
  closePanel?: () => void
  isPanelVisible?: () => boolean
} | null>(null)
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

const BP_BAND_FREQ: Record<AlgoBpKey, string> = {
  bpDelta: '<4 Hz',
  bpTheta: '4–8 Hz',
  bpAlpha: '8–13 Hz',
  bpBeta: '13–30 Hz',
  bpGamma: '>30 Hz',
}

const percentValueFormatter = new Intl.NumberFormat(undefined, {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
})

const absoluteValueFormatter = new Intl.NumberFormat(undefined, {
  maximumFractionDigits: 2,
  notation: 'compact',
})

const effectiveDataCorrection = computed<EegDataCorrection>(() => {
  if (props.dataCorrection !== 'calibrated') {
    return props.dataCorrection
  }

  return props.calibrationProfile?.isComplete === true ? 'calibrated' : 'raw'
})

const resolvedUiStateScope = computed<string | null>(() => {
  const rawScope = props.uiStateScope?.trim()
  return rawScope !== undefined && rawScope !== '' ? rawScope : null
})

const signalPanelEntries = computed(() => {
  const keys: readonly string[] = props.dataSource === 'algo-bp' ? ALGO_BP_KEYS : EEG_BAND_KEYS
  return keys.map((key) => ({
    key,
    label: t(`monitoring.series.${key}`),
  }))
})

const barStyleToken = computed(() => {
  return [...EEG_BAND_KEYS, ...ALGO_BP_KEYS]
    .map((key) => `${key}:${signalStyleStore.getSignalStyle(key).color}`)
    .join('|')
})

const chartSnapshot = computed(() => {
  if (props.data === null) {
    return null
  }

  if (props.dataSource === 'algo-bp') {
    const bpSnapshot = buildAlgoBpSnapshot(
      props.data,
      props.windowSec,
      props.anchorTimestampMs,
    )
    return bpSnapshot
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

  if (effectiveDataCorrection.value === 'calibrated' && props.calibrationProfile?.isComplete === true) {
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

const hasAnySamples = computed(() => {
  const snapshot = chartSnapshot.value
  if (snapshot === null) {
    return false
  }

  const counts = snapshot.sampleCounts as Record<string, number>
  if (props.dataSource === 'algo-bp') {
    return ALGO_BP_KEYS.some((key) => (counts[key] ?? 0) > 0)
  }

  return EEG_BAND_KEYS.some((bandKey) => (counts[bandKey] ?? 0) > 0)
})

const signalBadgeText = computed(() => {
  if (props.forceNoSignal) {
    return t('monitoring.badge.signalNone')
  }

  const value = poorSignalValue.value

  if (value === null) return t('monitoring.badge.signalNone')
  if (value === 0) return formatSignalBadgeText(t('monitoring.badge.signalGood'), value)
  if (value <= 25) return formatSignalBadgeText(t('monitoring.badge.signalFair'), value)
  return formatSignalBadgeText(t('monitoring.badge.signalPoor'), value)
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
  if (props.dataSource === 'algo-bp') {
    return absoluteValueFormatter.format(value)
  }

  if (effectiveDataCorrection.value === 'calibrated') {
    return `${percentValueFormatter.format(value)}%`
  }

  return absoluteValueFormatter.format(value)
}

function buildOption() {
  const snapshot = chartSnapshot.value
  const isAlgoBp = props.dataSource === 'algo-bp'
  const isPercentScale = !isAlgoBp && effectiveDataCorrection.value === 'calibrated'
  const labelFontSize = props.compact ? 10 : 11
  const freqFontSize = props.compact ? 9 : 10

  const activeKeys: readonly string[] = isAlgoBp ? ALGO_BP_KEYS : EEG_BAND_KEYS
  const categories = activeKeys.map((key) => ({
    value: key,
    textStyle: {},
  }))

  const freqMap: Record<string, string> = isAlgoBp ? BP_BAND_FREQ : BAND_FREQ
  const colorMap: Record<string, string> = Object.fromEntries(
    activeKeys.map((key) => [key, signalStyleStore.getSignalStyle(key).color]),
  ) as Record<string, string>
  const bandValues = snapshot?.bandValues as Record<string, number> | undefined
  const plottedValues = activeKeys.map((key) => (props.forceNoSignal ? 0 : (bandValues?.[key] ?? 0)))
  const yAxisMin = isAlgoBp ? Math.min(0, ...plottedValues) : 0
  const yAxisMax = isPercentScale
    ? 100
    : isAlgoBp
      ? Math.max(yAxisMin + 1, Math.max(0, ...plottedValues))
      : undefined

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
          const freq = freqMap[key] ?? ''
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
      min: yAxisMin,
      max: yAxisMax,
      name: props.compact
        ? ''
        : (isAlgoBp
          ? t('monitoring.axis.eegPower')
          : (isPercentScale
            ? t('monitoring.axis.eegCalibrated')
            : t('monitoring.axis.eegPower'))),
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
        data: activeKeys.map((key, index) => ({
          value: plottedValues[index],
          itemStyle: {
            color: colorMap[key] ?? '#888',
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
  barStyleToken.value
  props.compact
  props.dataCorrection
  props.dataSource
  effectiveDataCorrection.value
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
