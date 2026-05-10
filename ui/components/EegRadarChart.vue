<template>
  <div class="eeg-radar-chart" ref="chartRoot">
    <div v-if="signalBadgeText" class="eeg-radar-chart__badge" :style="{ color: signalBadgeColor }">
      {{ signalBadgeText }}
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watchEffect } from 'vue'
import { useI18n } from 'vue-i18n'
import { use, init, type ECharts } from 'echarts/core'
import { RadarChart } from 'echarts/charts'
import { RadarComponent, TooltipComponent, GraphicComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot, LogChartSeriesKey } from '@protocol'
import { EEG_BAND_COLORS } from '../services/eeg-band-colors'

use([RadarChart, RadarComponent, TooltipComponent, GraphicComponent, CanvasRenderer])

const RADAR_WINDOW_MS = 30_000

const props = defineProps<{
  readonly data: LogChartDataSnapshot
  readonly anchorTimestampMs?: number | null
}>()

const { t } = useI18n()
const chartRoot = ref<HTMLDivElement | null>(null)
let chartInstance: ECharts | null = null
let resizeObserver: ResizeObserver | null = null

type RadarBandKey = 'delta' | 'theta' | 'alpha1' | 'alpha2' | 'beta1' | 'beta2' | 'gamma1' | 'gamma2'
const RADAR_BAND_KEYS: readonly RadarBandKey[] = ['delta', 'theta', 'alpha1', 'alpha2', 'beta1', 'beta2', 'gamma1', 'gamma2']
const RADAR_DISPLAY_KEYS: readonly RadarBandKey[] = ['delta', 'gamma2', 'gamma1', 'beta2', 'beta1', 'alpha2', 'alpha1', 'theta']

const RADAR_OUTLINE_COLOR = 'rgba(255, 255, 255, 0.92)'
const RADAR_OUTLINE_FILL = 'rgba(255, 255, 255, 0.04)'
const RADAR_RADIUS_FACTOR = 0.37
const RADAR_BAND_FILL_OPACITY = 0.2
const RADAR_SPOKE_OPACITY = 0.72
const BAND_FREQ_LABELS: Record<RadarBandKey, string> = {
  delta: '0.5–4 Hz',
  theta: '4–8 Hz',
  alpha1: '8–10 Hz',
  alpha2: '10–13 Hz',
  beta1: '13–17 Hz',
  beta2: '17–30 Hz',
  gamma1: '30–40 Hz',
  gamma2: '40–100 Hz',
}

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

function hexToRgba(hex: string, alpha: number): string {
  const normalized = hex.replace('#', '')
  if (normalized.length !== 6) {
    return hex
  }

  const r = Number.parseInt(normalized.slice(0, 2), 16)
  const g = Number.parseInt(normalized.slice(2, 4), 16)
  const b = Number.parseInt(normalized.slice(4, 6), 16)

  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

function buildRadarSpokeGraphics() {
  const width = chartRoot.value?.clientWidth ?? 0
  const height = chartRoot.value?.clientHeight ?? 0
  if (width <= 0 || height <= 0) {
    return []
  }

  const centerX = width * 0.5
  const centerY = height * 0.5
  const radius = Math.min(width, height) * RADAR_RADIUS_FACTOR
  const angleStepDeg = 360 / RADAR_DISPLAY_KEYS.length

  return RADAR_DISPLAY_KEYS.map((bandKey, index) => {
    const angleDeg = 90 - index * angleStepDeg
    const angleRad = (angleDeg * Math.PI) / 180

    return {
      type: 'line',
      id: `radar-spoke-${bandKey}`,
      shape: {
        x1: centerX,
        y1: centerY,
        x2: centerX + radius * Math.cos(angleRad),
        y2: centerY - radius * Math.sin(angleRad),
      },
      style: {
        stroke: hexToRgba(EEG_BAND_COLORS[bandKey], RADAR_SPOKE_OPACITY),
        lineWidth: 1.5,
      },
      silent: true,
      z: 2,
    }
  })
}

const radarData = computed(() => {
  const maxTs = props.anchorTimestampMs ?? props.data.maxTimestampMs
  if (maxTs === null) return null

  const bandPoints: Record<RadarBandKey, readonly [number, number][]> = {
    delta: getSeriesPoints('delta'),
    theta: getSeriesPoints('theta'),
    alpha1: getSeriesPoints('alpha1'),
    alpha2: getSeriesPoints('alpha2'),
    beta1: getSeriesPoints('beta1'),
    beta2: getSeriesPoints('beta2'),
    gamma1: getSeriesPoints('gamma1'),
    gamma2: getSeriesPoints('gamma2'),
  }

  const bandAvgs = Object.fromEntries(
    RADAR_BAND_KEYS.map((key) => [key, avgLastWindow(bandPoints[key], maxTs)])
  ) as Record<RadarBandKey, number>

  const totalBand = Object.values(bandAvgs).reduce((s, v) => s + v, 0)
  const bandPcts = totalBand > 0
    ? Object.fromEntries(RADAR_BAND_KEYS.map((key) => [key, (bandAvgs[key] / totalBand) * 100])) as Record<RadarBandKey, number>
    : Object.fromEntries(RADAR_BAND_KEYS.map((key) => [key, 0])) as Record<RadarBandKey, number>

  return {
    bandPcts,
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
  const labelRich = Object.fromEntries(
    RADAR_DISPLAY_KEYS.map((key) => [key, {
      color: EEG_BAND_COLORS[key],
      fontSize: 11,
      lineHeight: 14,
      fontWeight: 600,
    }]),
  )

  const indicator = RADAR_DISPLAY_KEYS.map((key) => ({
    name: `{${key}|${t(`monitoring.series.${key}`)}}\n{${key}|${BAND_FREQ_LABELS[key]}}`,
    max: 100,
  }))

  const values = d !== null
    ? RADAR_DISPLAY_KEYS.map((key) => d.bandPcts[key])
    : RADAR_DISPLAY_KEYS.map(() => 0)

  const bandSeries = RADAR_DISPLAY_KEYS.map((bandKey, bandIndex) => ({
    type: 'radar' as const,
    name: bandKey,
    data: [{
      value: values.map((value, valueIndex) => (valueIndex === bandIndex ? value : 0)),
    }],
    lineStyle: { color: EEG_BAND_COLORS[bandKey], width: 2 },
    areaStyle: { color: hexToRgba(EEG_BAND_COLORS[bandKey], RADAR_BAND_FILL_OPACITY) },
    itemStyle: { color: EEG_BAND_COLORS[bandKey] },
    symbol: 'none',
    emphasis: { focus: 'series' as const },
    z: 10 + bandIndex,
  }))

  return {
    animation: false,
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'item',
      formatter: (params: { readonly seriesName?: string; readonly value?: number | number[] }) => {
        const bandKey = params.seriesName as RadarBandKey | '__outline' | undefined
        if (bandKey === undefined || bandKey === '__outline') {
          return ''
        }

        const bandIndex = RADAR_DISPLAY_KEYS.indexOf(bandKey)
        const values = Array.isArray(params.value) ? params.value : []
        const bandValue = bandIndex >= 0 ? values[bandIndex] ?? 0 : 0

        return `${t(`monitoring.series.${bandKey}`)}<br/>${BAND_FREQ_LABELS[bandKey]}: ${bandValue.toFixed(1)}%`
      },
    },
    graphic: buildRadarSpokeGraphics(),
    radar: {
      shape: 'polygon',
      center: ['50%', '50%'],
      radius: '74%',
      startAngle: 90,
      indicator,
      splitArea: {
        areaStyle: {
          color: ['rgba(255,255,255,0.02)', 'rgba(255,255,255,0.04)', 'rgba(255,255,255,0.06)', 'rgba(255,255,255,0.08)'],
        },
      },
      axisLine: { lineStyle: { color: 'rgba(255,255,255,0.15)' } },
      splitLine: { lineStyle: { color: 'rgba(255,255,255,0.12)' } },
      axisName: {
        fontSize: 11,
        lineHeight: 14,
        rich: labelRich,
      },
    },
    series: [
      ...bandSeries,
      {
        type: 'radar' as const,
        name: '__outline',
        silent: true,
        data: [{ value: values }],
        lineStyle: { color: RADAR_OUTLINE_COLOR, width: 1.5 },
        areaStyle: { color: RADAR_OUTLINE_FILL },
        itemStyle: { color: RADAR_OUTLINE_COLOR },
        symbol: 'none',
        z: 30,
      },
    ],
  }
}

function renderChart() {
  chartInstance?.setOption(buildRadarOption(), {
    notMerge: false,
    lazyUpdate: true,
    replaceMerge: ['series', 'radar', 'graphic'],
  })
}

function handleResize() {
  chartInstance?.resize()
  renderChart()
}

onMounted(() => {
  if (chartRoot.value === null) return
  chartInstance = init(chartRoot.value, undefined, { renderer: 'canvas' })
  renderChart()

  resizeObserver = new ResizeObserver(() => {
    handleResize()
  })
  resizeObserver.observe(chartRoot.value)
})

watchEffect(() => {
  radarData.value
  signalBadgeText.value
  signalBadgeColor.value
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
