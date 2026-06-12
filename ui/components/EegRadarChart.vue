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
    <div class="eeg-radar-chart" ref="chartRoot" />

    <template #overlay>
      <div v-if="signalBadgeText" class="eeg-radar-chart__badge" :style="{ color: signalBadgeColor }">
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
import { RadarChart } from 'echarts/charts'
import { RadarComponent, TooltipComponent, GraphicComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot } from '@protocol'
import EegChartSidePanelLayout from './EegChartSidePanelLayout.vue'
import EegSignalStyleListPanel from './EegSignalStyleListPanel.vue'
import type { EegDataCorrection, EegDataSource } from '../stores/preferences'
import type { EegCalibrationProfile } from '../stores/device'
import { useEegSignalStyleStore } from '../stores/eeg-signal-style'
import {
  type AlgoBpKey,
  type EegBandKey,
  buildAlgoBpSnapshot,
  buildEegBandAveragesSnapshot,
  calibrateBandValues,
  getLatestSeriesValue,
} from '../services/eeg-band-snapshot'

use([RadarChart, RadarComponent, TooltipComponent, GraphicComponent, CanvasRenderer])

const props = withDefaults(defineProps<{
  readonly data: LogChartDataSnapshot
  readonly anchorTimestampMs?: number | null
  readonly windowSec?: number
  readonly dataCorrection?: EegDataCorrection
  readonly calibrationProfile?: EegCalibrationProfile | null
  readonly dataSource?: EegDataSource
  readonly uiStateScope?: string | null
  readonly showSidePanelOpenButton?: boolean
}>(), {
  anchorTimestampMs: null,
  windowSec: 30,
  dataCorrection: 'raw',
  calibrationProfile: null,
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

const resolvedUiStateScope = computed<string | null>(() => {
  const rawScope = props.uiStateScope?.trim()
  return rawScope !== undefined && rawScope !== '' ? rawScope : null
})

type RadarBandKey = EegBandKey
const RADAR_DISPLAY_KEYS: readonly RadarBandKey[] = ['gamma2', 'gamma1', 'beta2', 'beta1', 'delta', 'theta', 'alpha1', 'alpha2']
const ALGO_BP_RADAR_KEYS: readonly AlgoBpKey[] = ['bpGamma', 'bpBeta', 'bpDelta', 'bpTheta', 'bpAlpha']

const RADAR_OUTLINE_COLOR = 'rgba(255, 255, 255, 0.92)'
const RADAR_OUTLINE_FILL = 'transparent'
const RADAR_START_ANGLE_DEG = 67.5
const RADAR_RADIUS_FACTOR = 0.37
const RADAR_SPLIT_COUNT = 5
const RADAR_BACKGROUND_CENTER_ALPHA = 0.085
const RADAR_BACKGROUND_EDGE_ALPHA = 0.028
const RADAR_BAND_FILL_OPACITY = 0.2
const RADAR_CENTER_HIGHLIGHT_OPACITY = 0.18
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

const ALGO_BP_FREQ_LABELS: Record<AlgoBpKey, string> = {
  bpDelta: '<4 Hz',
  bpTheta: '4–8 Hz',
  bpAlpha: '8–13 Hz',
  bpBeta: '13–30 Hz',
  bpGamma: '>30 Hz',
}

const displaySignalKeys = computed<readonly string[]>(() => {
  return props.dataSource === 'algo-bp' ? [...ALGO_BP_RADAR_KEYS] : [...RADAR_DISPLAY_KEYS]
})

const signalPanelEntries = computed(() => {
  return displaySignalKeys.value.map((key) => ({
    key,
    label: t(`monitoring.series.${key}`),
  }))
})

const radarStyleToken = computed(() => {
  return displaySignalKeys.value
    .map((key) => `${key}:${signalStyleStore.getSignalStyle(key).color}`)
    .join('|')
})

const rawValueFormatter = new Intl.NumberFormat(undefined, { maximumFractionDigits: 2, notation: 'compact' })

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

function getSignalColor(signalKey: string): string {
  return signalStyleStore.getSignalStyle(signalKey).color
}

function getRadarGeometry() {
  const width = chartRoot.value?.clientWidth ?? 0
  const height = chartRoot.value?.clientHeight ?? 0
  if (width <= 0 || height <= 0) {
    return null
  }

  const displayKeys = displaySignalKeys.value
  return {
    centerX: width * 0.5,
    centerY: height * 0.5,
    radius: Math.min(width, height) * RADAR_RADIUS_FACTOR,
    angleStepDeg: 360 / displayKeys.length,
    displayKeys,
  }
}

function buildRadarSpokeGraphics() {
  const geometry = getRadarGeometry()
  if (geometry === null) {
    return []
  }

  const { centerX, centerY, radius, angleStepDeg, displayKeys } = geometry

  return displayKeys.map((bandKey, index) => {
    const angleDeg = RADAR_START_ANGLE_DEG + index * angleStepDeg
    const angleRad = (angleDeg * Math.PI) / 180
    const color = getSignalColor(bandKey)

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
        stroke: color,
        lineWidth: 1.5,
      },
      silent: true,
      z: 2,
    }
  })
}

function buildRadarBackgroundGraphics() {
  const geometry = getRadarGeometry()
  if (geometry === null) {
    return []
  }

  const { centerX, centerY, radius, angleStepDeg, displayKeys } = geometry
  const points = displayKeys.map((_, index) => {
    const angleDeg = RADAR_START_ANGLE_DEG + index * angleStepDeg
    const angleRad = (angleDeg * Math.PI) / 180

    return [
      centerX + radius * Math.cos(angleRad),
      centerY - radius * Math.sin(angleRad),
    ]
  })

  return [{
    type: 'polygon',
    id: 'radar-background',
    shape: {
      points,
    },
    style: {
      fill: {
        type: 'radial',
        x: centerX,
        y: centerY,
        r: radius,
        colorStops: [
          { offset: 0, color: `rgba(255,255,255,${RADAR_BACKGROUND_CENTER_ALPHA})` },
          { offset: 0.55, color: 'rgba(255,255,255,0.055)' },
          { offset: 1, color: `rgba(255,255,255,${RADAR_BACKGROUND_EDGE_ALPHA})` },
        ],
        global: true,
      },
    },
    silent: true,
    z: 0,
  }]
}

function buildRadarSectorGraphics(values: readonly number[], axisMin: number, axisMax: number) {
  const geometry = getRadarGeometry()
  const axisRange = axisMax - axisMin
  if (geometry === null || axisRange <= 0) {
    return []
  }

  const { centerX, centerY, radius, angleStepDeg, displayKeys } = geometry

  return displayKeys.flatMap((bandKey, index) => {
    const nextIndex = (index + 1) % displayKeys.length
    const nextBandKey = displayKeys[nextIndex]
    const valueRatio = Math.max(0, Math.min(1, (values[index] - axisMin) / axisRange))
    const nextValueRatio = Math.max(0, Math.min(1, (values[nextIndex] - axisMin) / axisRange))
    const angleDeg = RADAR_START_ANGLE_DEG + index * angleStepDeg
    const nextAngleDeg = RADAR_START_ANGLE_DEG + nextIndex * angleStepDeg
    const angleRad = (angleDeg * Math.PI) / 180
    const nextAngleRad = (nextAngleDeg * Math.PI) / 180

    const pointX = centerX + radius * valueRatio * Math.cos(angleRad)
    const pointY = centerY - radius * valueRatio * Math.sin(angleRad)
    const nextPointX = centerX + radius * nextValueRatio * Math.cos(nextAngleRad)
    const nextPointY = centerY - radius * nextValueRatio * Math.sin(nextAngleRad)
    const sectorPoints = [
      [centerX, centerY],
      [pointX, pointY],
      [nextPointX, nextPointY],
    ] as const
    const sectorRadius = Math.max(1, radius * Math.max(valueRatio, nextValueRatio))

    const color0 = getSignalColor(bandKey)
    const color1 = getSignalColor(nextBandKey)

    return [
      {
        type: 'polygon',
        id: `radar-sector-${bandKey}`,
        shape: {
          points: sectorPoints,
        },
        style: {
          fill: {
            type: 'linear',
            x: pointX,
            y: pointY,
            x2: nextPointX,
            y2: nextPointY,
            colorStops: [
              { offset: 0, color: hexToRgba(color0, RADAR_BAND_FILL_OPACITY) },
              { offset: 1, color: hexToRgba(color1, RADAR_BAND_FILL_OPACITY) },
            ],
            global: true,
          },
        },
        silent: true,
        z: 6,
      },
      {
        type: 'polygon',
        id: `radar-sector-highlight-${bandKey}`,
        shape: {
          points: sectorPoints,
        },
        style: {
          fill: {
            type: 'radial',
            x: centerX,
            y: centerY,
            r: sectorRadius,
            colorStops: [
              { offset: 0, color: `rgba(255,255,255,${RADAR_CENTER_HIGHLIGHT_OPACITY})` },
              { offset: 0.6, color: 'rgba(255,255,255,0.05)' },
              { offset: 1, color: 'rgba(255,255,255,0)' },
            ],
            global: true,
          },
        },
        silent: true,
        z: 7,
      },
    ]
  })
}

const effectiveDataCorrection = computed<EegDataCorrection>(() => {
  if (props.dataCorrection !== 'calibrated') return props.dataCorrection
  return props.calibrationProfile?.isComplete === true ? 'calibrated' : 'raw'
})

const radarData = computed(() => {
  if (props.dataSource === 'algo-bp') {
    const bpSnapshot = buildAlgoBpSnapshot(props.data, props.windowSec, props.anchorTimestampMs)
    if (bpSnapshot === null) return null

    const displayValues = bpSnapshot.bandValues as Record<string, number>
    const axisMin = Math.min(0, ...Object.values(bpSnapshot.bandValues))
    const axisMax = Math.max(axisMin + 1, Math.max(0, ...Object.values(bpSnapshot.bandValues)))
    return { displayValues, axisMin, axisMax, isPercent: false }
  }

  const bandSnapshot = buildEegBandAveragesSnapshot(props.data, props.windowSec, props.anchorTimestampMs)
  if (bandSnapshot === null) return null

  const rawBandValues = bandSnapshot.bandValues
  let displayValues: Record<RadarBandKey, number>
  let axisMin = 0
  let axisMax: number
  let isPercent: boolean

  if (effectiveDataCorrection.value === 'calibrated') {
    const calib = calibrateBandValues(
      rawBandValues,
      props.calibrationProfile!.deviceWideMin,
      props.calibrationProfile!.deviceWideMax,
    )
    displayValues = calib as Record<RadarBandKey, number>
    axisMax = 100
    isPercent = true
  } else {
    displayValues = rawBandValues as Record<RadarBandKey, number>
    axisMax = Math.max(1, ...Object.values(rawBandValues))
    isPercent = false
  }

  return { displayValues, axisMin, axisMax, isPercent }
})

// PoorSignal badge — resolved at anchorTimestampMs, not the last session point
const signalBadgeText = computed(() => {
  const series = props.data.series.find((item) => item.key === 'poorSignal')
  if (!series || series.points.length === 0) return null
  const value = getLatestSeriesValue(props.data, 'poorSignal', props.anchorTimestampMs)
  if (value === null) return t('monitoring.badge.signalNone')
  if (value === 0) return formatSignalBadgeText(t('monitoring.badge.signalGood'), value)
  if (value <= 25) return formatSignalBadgeText(t('monitoring.badge.signalFair'), value)
  return formatSignalBadgeText(t('monitoring.badge.signalPoor'), value)
})

const signalBadgeColor = computed(() => {
  const series = props.data.series.find((item) => item.key === 'poorSignal')
  if (!series || series.points.length === 0) return '#9aa5b1'
  const value = getLatestSeriesValue(props.data, 'poorSignal', props.anchorTimestampMs)
  if (value === null) return '#9aa5b1'
  if (value === 0) return '#43aa8b'
  if (value <= 25) return '#f9c74f'
  return '#e76f51'
})

function buildRadarOption() {
  const d = radarData.value
  const axisMin = d?.axisMin ?? 0
  const axisMax = d?.axisMax ?? 100
  const isPercent = d?.isPercent ?? true
  const isAlgoBp = props.dataSource === 'algo-bp'
  const displayKeys: readonly string[] = displaySignalKeys.value
  const freqLabels: Record<string, string> = isAlgoBp ? ALGO_BP_FREQ_LABELS : BAND_FREQ_LABELS
  const bandColors: Record<string, string> = Object.fromEntries(
    displayKeys.map((key) => [key, getSignalColor(key)]),
  ) as Record<string, string>

  const labelRich = Object.fromEntries(
    displayKeys.map((key) => [key, {
      color: bandColors[key] ?? '#888',
      fontSize: 11,
      lineHeight: 14,
      fontWeight: 600,
    }]),
  )

  const indicator = displayKeys.map((key) => ({
    name: `{${key}|${t(`monitoring.series.${key}`)}}\n{${key}|${freqLabels[key] ?? ''}}`,
    min: axisMin,
    max: axisMax,
  }))

  const values = d !== null
    ? displayKeys.map((key) => (d.displayValues as Record<string, number>)[key] ?? 0)
    : displayKeys.map(() => 0)

  const bandSeries = displayKeys.map((bandKey, bandIndex) => {
    const nextBandIndex = (bandIndex + 1) % displayKeys.length

    return {
      type: 'radar' as const,
      name: bandKey,
      data: [{
        value: values.map((value, valueIndex) => (valueIndex === bandIndex || valueIndex === nextBandIndex ? value : 0)),
      }],
      lineStyle: { color: 'transparent', width: 0, opacity: 0 },
      areaStyle: { color: 'transparent', opacity: 0 },
      itemStyle: { color: 'transparent', opacity: 0 },
      symbol: 'none',
      emphasis: { focus: 'series' as const },
      z: 10 + bandIndex,
    }
  })

  return {
    animation: false,
    backgroundColor: 'transparent',
    tooltip: {
      trigger: 'item',
      formatter: (params: { readonly seriesName?: string; readonly value?: number | number[] }) => {
        const bandKey = params.seriesName as string | '__outline' | undefined
        if (bandKey === undefined || bandKey === '__outline') {
          return ''
        }

        const bandIndex = displayKeys.indexOf(bandKey)
        const vals = Array.isArray(params.value) ? params.value : []
        const bandValue = bandIndex >= 0 ? vals[bandIndex] ?? 0 : 0
        const formatted = isPercent
          ? `${bandValue.toFixed(1)}%`
          : rawValueFormatter.format(bandValue)

        return `${t(`monitoring.series.${bandKey}`)}<br/>${freqLabels[bandKey] ?? ''}: ${formatted}`
      },
    },
    graphic: [...buildRadarBackgroundGraphics(), ...buildRadarSectorGraphics(values, axisMin, axisMax), ...buildRadarSpokeGraphics()],
    radar: {
      shape: 'polygon',
      center: ['50%', '50%'],
      radius: '74%',
      startAngle: RADAR_START_ANGLE_DEG,
      splitNumber: RADAR_SPLIT_COUNT,
      indicator,
      splitArea: { show: false },
      axisLine: { show: false },
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
  radarStyleToken.value
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
.eeg-radar-chart {
  position: relative;
  width: 100%;
  height: 100%;
  min-height: 320px;
}

.eeg-radar-chart__badge {
  font-size: 11px;
  background: rgba(0, 0, 0, 0.35);
  padding: 2px 8px;
  border-radius: 4px;
  pointer-events: none;
  z-index: 1;
}
</style>
