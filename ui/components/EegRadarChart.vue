<template>
  <div class="eeg-radar-chart" ref="chartRoot">
    <div v-if="signalBadgeText" class="eeg-radar-chart__badge" :style="{ color: signalBadgeColor }">
      {{ signalBadgeText }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { use, init, type ECharts } from 'echarts/core'
import { RadarChart } from 'echarts/charts'
import { RadarComponent, TooltipComponent, LegendComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot, LogChartSeriesKey } from '@protocol'

use([RadarChart, RadarComponent, TooltipComponent, LegendComponent, CanvasRenderer])

const RADAR_WINDOW_MS = 30_000

const props = defineProps<{
  readonly data: LogChartDataSnapshot
}>()

const { t } = useI18n()
const chartRoot = ref<HTMLDivElement | null>(null)
let chartInstance: ECharts | null = null
let resizeObserver: ResizeObserver | null = null

type CombinedBandKey = 'delta' | 'theta' | 'alpha' | 'beta' | 'gamma'
const COMBINED_BAND_KEYS: readonly CombinedBandKey[] = ['delta', 'theta', 'alpha', 'beta', 'gamma']

const LABEL_COLOR = 'rgba(255, 255, 255, 0.65)'
const AREA_COLOR = 'rgba(67, 170, 139, 0.25)'
const LINE_COLOR = '#43aa8b'

function getSeriesPoints(key: LogChartSeriesKey): readonly [number, number][] {
  const s = props.data.series.find((item) => item.key === key)
  return (s?.points ?? []) as readonly [number, number][]
}

function sumPairPoints(keyA: LogChartSeriesKey, keyB: LogChartSeriesKey): readonly [number, number][] {
  const a = getSeriesPoints(keyA)
  const b = getSeriesPoints(keyB)
  if (a.length === 0) return b
  if (b.length === 0) return a
  const mapB = new Map(b.map((p) => [p[0], p[1]]))
  return a.map((p) => [p[0], p[1] + (mapB.get(p[0]) ?? 0)] as [number, number])
}

function avgLastWindow(points: readonly [number, number][], maxTs: number): number {
  const windowStart = maxTs - RADAR_WINDOW_MS
  const windowPoints = points.filter((p) => p[0] >= windowStart)
  if (windowPoints.length === 0) return 0
  return windowPoints.reduce((sum, p) => sum + p[1], 0) / windowPoints.length
}

const radarData = computed(() => {
  const maxTs = props.data.maxTimestampMs
  if (maxTs === null) return null

  const bandPoints: Record<CombinedBandKey, readonly [number, number][]> = {
    delta: getSeriesPoints('delta'),
    theta: getSeriesPoints('theta'),
    alpha: sumPairPoints('alpha1', 'alpha2'),
    beta: sumPairPoints('beta1', 'beta2'),
    gamma: sumPairPoints('gamma1', 'gamma2'),
  }

  const bandAvgs: Record<CombinedBandKey, number> = {
    delta: avgLastWindow(bandPoints.delta, maxTs),
    theta: avgLastWindow(bandPoints.theta, maxTs),
    alpha: avgLastWindow(bandPoints.alpha, maxTs),
    beta: avgLastWindow(bandPoints.beta, maxTs),
    gamma: avgLastWindow(bandPoints.gamma, maxTs),
  }

  const totalBand = Object.values(bandAvgs).reduce((s, v) => s + v, 0)
  const bandPcts = totalBand > 0
    ? Object.fromEntries(COMBINED_BAND_KEYS.map((k) => [k, (bandAvgs[k] / totalBand) * 100])) as Record<CombinedBandKey, number>
    : Object.fromEntries(COMBINED_BAND_KEYS.map((k) => [k, 0])) as Record<CombinedBandKey, number>

  const attentionAvg = avgLastWindow(getSeriesPoints('attention'), maxTs)
  const meditationAvg = avgLastWindow(getSeriesPoints('meditation'), maxTs)

  return {
    bandPcts,
    attention: Math.min(100, attentionAvg),
    meditation: Math.min(100, meditationAvg),
  }
})

// PoorSignal badge
const signalBadgeText = computed(() => {
  const s = props.data.series.find((item) => item.key === 'poorSignal')
  if (!s || s.points.length === 0) return null
  const value = s.points.at(-1)?.[1] ?? null
  if (value === null) return t('monitoring.badge.signalNone')
  if (value === 0) return t('monitoring.badge.signalGood')
  if (value <= 25) return t('monitoring.badge.signalFair')
  return t('monitoring.badge.signalPoor')
})

const signalBadgeColor = computed(() => {
  const s = props.data.series.find((item) => item.key === 'poorSignal')
  if (!s || s.points.length === 0) return '#9aa5b1'
  const value = s.points.at(-1)?.[1] ?? null
  if (value === null) return '#9aa5b1'
  if (value === 0) return '#43aa8b'
  if (value <= 25) return '#f9c74f'
  return '#e76f51'
})

function buildRadarOption() {
  const d = radarData.value
  const indicator = [
    { name: t('monitoring.series.attention'), max: 100 },
    { name: t('monitoring.series.meditation'), max: 100 },
    { name: t('monitoring.series.delta'), max: 100 },
    { name: t('monitoring.series.theta'), max: 100 },
    { name: t('monitoring.series.alpha'), max: 100 },
    { name: t('monitoring.series.beta'), max: 100 },
    { name: t('monitoring.series.gamma'), max: 100 },
  ]

  const values = d !== null
    ? [d.attention, d.meditation, d.bandPcts.delta, d.bandPcts.theta, d.bandPcts.alpha, d.bandPcts.beta, d.bandPcts.gamma]
    : [0, 0, 0, 0, 0, 0, 0]

  return {
    animation: false,
    backgroundColor: 'transparent',
    radar: {
      shape: 'polygon',
      center: ['50%', '50%'],
      radius: '65%',
      indicator,
      splitArea: {
        areaStyle: {
          color: ['rgba(255,255,255,0.02)', 'rgba(255,255,255,0.04)', 'rgba(255,255,255,0.06)', 'rgba(255,255,255,0.08)'],
        },
      },
      axisLine: { lineStyle: { color: 'rgba(255,255,255,0.15)' } },
      splitLine: { lineStyle: { color: 'rgba(255,255,255,0.12)' } },
      axisName: { color: LABEL_COLOR, fontSize: 12 },
    },
    series: [{
      type: 'radar' as const,
      data: [{
        value: values,
        name: t('monitoring.axis.eeg'),
        areaStyle: { color: AREA_COLOR },
        lineStyle: { color: LINE_COLOR, width: 2 },
        itemStyle: { color: LINE_COLOR },
      }],
    }],
  }
}

function renderChart() {
  chartInstance?.setOption(buildRadarOption(), {
    notMerge: false,
    lazyUpdate: true,
    replaceMerge: ['series', 'radar'],
  })
}

onMounted(() => {
  if (chartRoot.value === null) return
  chartInstance = init(chartRoot.value, undefined, { renderer: 'canvas' })
  renderChart()

  resizeObserver = new ResizeObserver(() => {
    chartInstance?.resize()
  })
  resizeObserver.observe(chartRoot.value)
})

watch(() => props.data, renderChart)

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  resizeObserver = null
  chartInstance?.dispose()
  chartInstance = null
})
</script>

<style scoped>
.eeg-radar-chart {
  position: relative;
  width: 100%;
  height: 100%;
  min-height: 320px;
}

.eeg-radar-chart__badge {
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
