<template>
  <div ref="chartRoot" class="device-data-chart" />
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { use, init, type ComposeOption, type ECharts } from 'echarts/core'
import { LineChart, ScatterChart, HeatmapChart, type LineSeriesOption, type ScatterSeriesOption, type HeatmapSeriesOption } from 'echarts/charts'
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  DataZoomComponent,
  GraphicComponent,
  VisualMapComponent,
  type GridComponentOption,
  type TooltipComponentOption,
  type LegendComponentOption,
  type DataZoomComponentOption,
  type GraphicComponentOption,
  type VisualMapComponentOption,
} from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot, LogChartPanel, LogChartSeries, LogChartSeriesKey } from '@protocol'
import type { EegDisplayMode } from '../stores/preferences'

use([LineChart, ScatterChart, HeatmapChart, GridComponent, TooltipComponent, LegendComponent, DataZoomComponent, GraphicComponent, VisualMapComponent, CanvasRenderer])

type MonitoringChartOption = ComposeOption<
  | LineSeriesOption
  | ScatterSeriesOption
  | HeatmapSeriesOption
  | GridComponentOption
  | TooltipComponentOption
  | LegendComponentOption
  | DataZoomComponentOption
  | GraphicComponentOption
  | VisualMapComponentOption
>

type ChartSeriesOption = LineSeriesOption | ScatterSeriesOption | HeatmapSeriesOption
type ChartViewportPreset = 'fit' | 'recent'

interface BuiltSeriesEntry {
  readonly option: ChartSeriesOption
  readonly defaultVisible: boolean
}

interface ChartAxisLayout {
  readonly panelIndexByName: Readonly<Record<LogChartPanel, number | null>>
  readonly valueAxisIndexByPanel: Readonly<Record<LogChartPanel, number | null>>
  readonly rrAxisIndex: number | null
}

type ChartGridLayoutKey =
  | 'ecg'
  | 'breath'
  | 'eeg'
  | 'ecg-breath'
  | 'ecg-eeg'
  | 'breath-eeg'
  | 'ecg-breath-eeg'

const LIVE_WINDOW_MS = 5 * 60 * 1000
const ECG_SERIES_STROKE_WIDTH = 1.5
const RR_SYMBOL_SIZE = 2
const TIME_AXIS_SECONDS_WINDOW_MS = 10 * 60 * 1000
const TIME_AXIS_DAY_WINDOW_MS = 24 * 60 * 60 * 1000
const TIME_AXIS_ROTATE_WINDOW_MS = 60 * 60 * 1000
const TIME_AXIS_LABEL_COLOR = 'rgba(255, 255, 255, 0.65)'
const TIME_AXIS_LINE_COLOR = 'rgba(255, 255, 255, 0.3)'
const TIME_AXIS_GRAPHIC_RIGHT_GAP = 18
const TIME_AXIS_LABEL_FONT_SIZE = 11
const TIME_AXIS_TICK_LENGTH = 6
const TIME_AXIS_LABEL_MARGIN = 8
const TIME_AXIS_GRAPHIC_VERTICAL_OFFSET = 0
const BREATH_PHASE_VISUAL_SCALE = 0.175
const BREATH_AXIS_TARGET_PADDING_PX = 20
const BREATH_PHASE_AXIS_EXTENT = 1
const BREATH_AXIS_LABEL_FONT_SIZE = 11
const CHART_GRID_LEFT = 84
const CHART_GRID_RIGHT = 64
const CHART_GRID_TOP = 56
const CHART_GRID_BOTTOM = 46
const LEFT_AXIS_LABEL_MARGIN = 44
const LEFT_AXIS_NAME_GAP = 44
const PANEL_TITLE_LEFT_OFFSET = 0
const PANEL_TITLE_TOP_GAP = 4
const BREATH_PHASE_COLORS = {
  inhale: {
    line: '#2a9d8f',
    area: 'rgba(42, 157, 143, 0.18)',
  },
  exhale: {
    line: '#e76f51',
    area: 'rgba(231, 111, 81, 0.18)',
  },
} as const
const PANEL_ORDER: readonly LogChartPanel[] = ['ecg', 'breath', 'eeg']
const SINGLE_PANEL_GRID: readonly GridComponentOption[] = [{
  left: CHART_GRID_LEFT,
  right: CHART_GRID_RIGHT,
  top: CHART_GRID_TOP,
  bottom: CHART_GRID_BOTTOM,
}]
const ECG_BREATH_GRID: readonly GridComponentOption[] = [
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, bottom: '25%' },
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, height: '12.8%', bottom: CHART_GRID_BOTTOM },
]
const SPLIT_TWO_PANEL_GRID: readonly GridComponentOption[] = [
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '38%' },
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '52%', bottom: CHART_GRID_BOTTOM },
]
const BREATH_EEG_GRID: readonly GridComponentOption[] = [
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '14.25%' },
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '52%', bottom: CHART_GRID_BOTTOM },
]
const THREE_PANEL_GRID: readonly GridComponentOption[] = [
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '27%' },
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '46%', height: '3.375%' },
  { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '66%', bottom: CHART_GRID_BOTTOM },
]
const GRID_LAYOUT_BY_KEY: Readonly<Record<ChartGridLayoutKey, readonly GridComponentOption[]>> = {
  ecg: SINGLE_PANEL_GRID,
  breath: SINGLE_PANEL_GRID,
  eeg: SINGLE_PANEL_GRID,
  'ecg-breath': ECG_BREATH_GRID,
  'ecg-eeg': SPLIT_TWO_PANEL_GRID,
  'breath-eeg': BREATH_EEG_GRID,
  'ecg-breath-eeg': THREE_PANEL_GRID,
}

const props = withDefaults(defineProps<{
  readonly data: LogChartDataSnapshot
  readonly mode: 'live' | 'loaded'
  readonly eegMode?: EegDisplayMode
  readonly viewportPreset?: ChartViewportPreset
  readonly viewportToken?: number
}>(), {
  viewportPreset: 'fit',
  viewportToken: 0,
  eegMode: 'lines',
})

const { t, locale } = useI18n()
const chartRoot = ref<HTMLDivElement | null>(null)
const legendSelection = ref<Record<string, boolean> | null>(null)

let resizeObserver: ResizeObserver | null = null
let chartInstance: ECharts | null = null
let lastPointCount = 0

const seriesColorByKey: Record<LogChartSeriesKey, string> = {
  hr: '#ff6b6b',
  rr: '#4dd0e1',
  breath_phase: BREATH_PHASE_COLORS.inhale.line,
  raw: '#9d4edd',
  poorSignal: '#9aa5b1',
  attention: '#2a9d8f',
  meditation: '#457b9d',
  delta: '#8ecae6',
  theta: '#219ebc',
  alpha1: '#90be6d',
  alpha2: '#43aa8b',
  beta1: '#f9c74f',
  beta2: '#f8961e',
  gamma1: '#f3722c',
  gamma2: '#e76f51',
}

function labelForSeries(key: LogChartSeriesKey): string {
  return t(`monitoring.series.${key}`)
}

function getPointCount(snapshot: LogChartDataSnapshot): number {
  return snapshot.series.reduce((total, series) => total + series.points.length, 0)
}

function createLegendSelection(entries: readonly BuiltSeriesEntry[]): Record<string, boolean> {
  const currentSelection = legendSelection.value

  return Object.fromEntries(entries.map((entry) => {
    const name = String(entry.option.name)
    return [name, currentSelection?.[name] ?? entry.defaultVisible]
  }))
}

function resolveZoomDefaults(snapshot: LogChartDataSnapshot, preset: ChartViewportPreset) {
  if (
    preset === 'recent' &&
    snapshot.minTimestampMs !== null &&
    snapshot.maxTimestampMs !== null &&
    snapshot.maxTimestampMs - snapshot.minTimestampMs > LIVE_WINDOW_MS
  ) {
    return {
      startValue: snapshot.maxTimestampMs - LIVE_WINDOW_MS,
      endValue: snapshot.maxTimestampMs,
    }
  }

  return {
    start: 0,
    end: 100,
  }
}

function getTimeRangeMs(snapshot: LogChartDataSnapshot): number | null {
  if (snapshot.minTimestampMs === null || snapshot.maxTimestampMs === null) {
    return null
  }

  return Math.max(0, snapshot.maxTimestampMs - snapshot.minTimestampMs)
}

function parseTimeAxisValueMs(value: number | string): number | null {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null
  }

  const trimmedValue = value.trim()
  if (trimmedValue === '') {
    return null
  }

  const numericValue = Number(trimmedValue)
  if (Number.isFinite(numericValue)) {
    return numericValue
  }

  const parsedDateValue = Date.parse(trimmedValue)
  return Number.isFinite(parsedDateValue) ? parsedDateValue : null
}

function getTimeAxisFormatOptions(rangeMs: number | null): Intl.DateTimeFormatOptions {
  if (rangeMs !== null && rangeMs >= TIME_AXIS_DAY_WINDOW_MS) {
    return {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }
  }

  if (rangeMs !== null && rangeMs <= TIME_AXIS_SECONDS_WINDOW_MS) {
    return {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    }
  }

  return {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }
}

function createTimeAxisLabelFormatter(rangeMs: number | null, language: string) {
  const formatter = new Intl.DateTimeFormat(language, getTimeAxisFormatOptions(rangeMs))

  return (value: number | string): string => {
    const timestampMs = parseTimeAxisValueMs(value)
    if (timestampMs === null) {
      return typeof value === 'string' ? value : ''
    }

    return formatter.format(new Date(timestampMs))
  }
}

function resolveVisiblePanels(snapshot: LogChartDataSnapshot): readonly LogChartPanel[] {
  const visiblePanels = new Set<LogChartPanel>()

  for (const item of snapshot.series) {
    if (item.points.length > 0) {
      visiblePanels.add(item.panel)
    }
  }

  const panels = PANEL_ORDER.filter((panel) => visiblePanels.has(panel))
  return panels.length > 0 ? panels : ['ecg']
}

// ─── EEG band utilities ───────────────────────────────────────────────────────

const EEG_BAND_KEYS: readonly LogChartSeriesKey[] = ['delta', 'theta', 'alpha1', 'alpha2', 'beta1', 'beta2', 'gamma1', 'gamma2']
const COMBINED_BAND_KEYS = ['delta', 'theta', 'alpha', 'beta', 'gamma'] as const
type CombinedBandKey = (typeof COMBINED_BAND_KEYS)[number]

interface CombinedBandSeries {
  readonly key: CombinedBandKey
  readonly points: readonly [number, number][]
}

const combinedBandColor: Record<CombinedBandKey, string> = {
  delta: '#8ecae6',
  theta: '#219ebc',
  alpha: '#90be6d',
  beta: '#f9c74f',
  gamma: '#f3722c',
}

function combineEegBands(series: readonly LogChartSeries[]): readonly CombinedBandSeries[] {
  const byKey = new Map<LogChartSeriesKey, readonly [number, number][]>()
  for (const s of series) {
    if ((EEG_BAND_KEYS as readonly string[]).includes(s.key)) {
      byKey.set(s.key, s.points as readonly [number, number][])
    }
  }

  function sumPairs(keyA: LogChartSeriesKey, keyB: LogChartSeriesKey): readonly [number, number][] {
    const a = byKey.get(keyA) ?? []
    const b = byKey.get(keyB) ?? []
    if (a.length === 0) return b as [number, number][]
    if (b.length === 0) return a as [number, number][]
    const mapB = new Map(b.map((p) => [p[0], p[1]]))
    return a.map((p) => [p[0], p[1] + (mapB.get(p[0]) ?? 0)] as [number, number])
  }

  return [
    { key: 'delta', points: byKey.get('delta') as readonly [number, number][] ?? [] },
    { key: 'theta', points: byKey.get('theta') as readonly [number, number][] ?? [] },
    { key: 'alpha', points: sumPairs('alpha1', 'alpha2') },
    { key: 'beta', points: sumPairs('beta1', 'beta2') },
    { key: 'gamma', points: sumPairs('gamma1', 'gamma2') },
  ]
}

function normalizeBandsByTimestamp(bands: readonly CombinedBandSeries[]): readonly CombinedBandSeries[] {
  // collect all timestamps from delta (reference band) — they should be aligned
  const refPoints = bands[0]?.points ?? []

  return bands.map((band) => {
    const byTs = new Map(band.points.map((p) => [p[0], p[1]]))
    const normalized: [number, number][] = refPoints.map((ref) => {
      const ts = ref[0]
      // compute total band power at this timestamp
      let total = 0
      for (const b of bands) {
        const bByTs = new Map(b.points.map((p) => [p[0], p[1]]))
        total += bByTs.get(ts) ?? 0
      }
      const value = byTs.get(ts) ?? 0
      return [ts, total > 0 ? (value / total) * 100 : 0]
    })
    return { key: band.key, points: normalized }
  })
}

// ─── PoorSignal badge ─────────────────────────────────────────────────────────

function getLatestPoorSignal(snapshot: LogChartDataSnapshot): number | null {
  const s = snapshot.series.find((item) => item.key === 'poorSignal')
  if (s === undefined || s.points.length === 0) return null
  const last = s.points.at(-1)
  return last !== undefined ? last[1] : null
}

function poorSignalBadgeText(value: number | null): string {
  if (value === null) return t('monitoring.badge.signalNone')
  if (value === 0) return t('monitoring.badge.signalGood')
  if (value <= 25) return t('monitoring.badge.signalFair')
  return t('monitoring.badge.signalPoor')
}

function poorSignalBadgeColor(value: number | null): string {
  if (value === null) return '#9aa5b1'
  if (value === 0) return '#43aa8b'
  if (value <= 25) return '#f9c74f'
  return '#e76f51'
}

function buildPoorSignalBadge(snapshot: LogChartDataSnapshot, chartWidth: number, chartHeight: number, topOffset = 4): GraphicComponentOption {
  const value = getLatestPoorSignal(snapshot)
  const text = poorSignalBadgeText(value)
  const color = poorSignalBadgeColor(value)

  return {
    type: 'text',
    right: CHART_GRID_RIGHT,
    top: topOffset,
    silent: true,
    style: {
      text,
      fill: color,
      fontSize: 11,
      align: 'right',
      verticalAlign: 'top',
      backgroundColor: 'rgba(0,0,0,0.35)',
      padding: [2, 6, 2, 6],
      borderRadius: 4,
    },
  }
}

// ─── Subpanels mode ───────────────────────────────────────────────────────────

// Additional grid constants for subpanels: EEG area is split into attention/meditation top + bands bottom
// When eeg-only the chart is split across the full height
const SUBPANELS_SCORE_HEIGHT_PCT = '28%'
const SUBPANELS_BANDS_HEIGHT_PCT = '40%'

// grid layout keys for subpanels mode — suffix '-sp'
type ChartGridLayoutKeySP = `${ChartGridLayoutKey}-sp`

function buildSubpanelGridLayout(panels: readonly LogChartPanel[], hasScoreData: boolean): GridComponentOption[] {
  const nonEegPanels = panels.filter((p) => p !== 'eeg')

  if (panels.length === 1 && panels[0] === 'eeg') {
    // EEG only
    if (hasScoreData) {
      return [
        { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '28%' }, // score
        { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '44%', bottom: CHART_GRID_BOTTOM }, // bands
      ]
    }
    return [
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, bottom: CHART_GRID_BOTTOM }, // bands only
    ]
  }

  // ECG only (no eeg) — fall through to standard layout; caller handles
  if (!panels.includes('eeg')) {
    return buildGridLayout(panels)
  }

  // Mixed: non-eeg panels take ~45%, eeg area takes ~55%
  if (nonEegPanels.length === 1 && nonEegPanels[0] === 'ecg') {
    if (hasScoreData) {
      return [
        { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '32%' }, // ecg
        { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '50%', height: '18%' }, // score
        { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '72%', bottom: CHART_GRID_BOTTOM }, // bands
      ]
    }
    return [
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '38%' }, // ecg
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '52%', bottom: CHART_GRID_BOTTOM }, // bands
    ]
  }

  if (nonEegPanels.length === 1 && nonEegPanels[0] === 'breath') {
    if (hasScoreData) {
      return [
        { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '10%' }, // breath
        { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '28%', height: '22%' }, // score
        { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '56%', bottom: CHART_GRID_BOTTOM }, // bands
      ]
    }
    return [
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '14%' }, // breath
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '32%', bottom: CHART_GRID_BOTTOM }, // bands
    ]
  }

  // ecg + breath + eeg
  if (hasScoreData) {
    return [
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '22%' }, // ecg
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '38%', height: '5%' }, // breath
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '52%', height: '16%' }, // score
      { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '74%', bottom: CHART_GRID_BOTTOM }, // bands
    ]
  }
  return [
    { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: CHART_GRID_TOP, height: '24%' }, // ecg
    { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '40%', height: '5%' }, // breath
    { left: CHART_GRID_LEFT, right: CHART_GRID_RIGHT, top: '54%', bottom: CHART_GRID_BOTTOM }, // bands
  ]
}

function buildSubpanelsAxisLayout(panels: readonly LogChartPanel[], hasScoreData: boolean) {
  const nonEegPanels = panels.filter((p) => p !== 'eeg')
  const hasEeg = panels.includes('eeg')

  let gridOffset = 0 // index into the grid array for non-eeg panels
  const panelIndexByName: Record<LogChartPanel, number | null> = { ecg: null, breath: null, eeg: null }
  const yAxis: MonitoringChartOption['yAxis'] = []
  let rrAxisIndex: number | null = null

  // Non-EEG panels come first (same order as PANEL_ORDER minus eeg)
  for (const panel of nonEegPanels) {
    const gridIndex = gridOffset++
    panelIndexByName[panel] = gridIndex

    if (panel === 'ecg') {
      yAxis.push({ type: 'value', gridIndex, axisLabel: createLeftAxisLabelStyle(), scale: true })
      rrAxisIndex = yAxis.length
      yAxis.push({ type: 'value', gridIndex, name: t('monitoring.axis.rr'), position: 'right', scale: true })
    } else if (panel === 'breath') {
      yAxis.push({
        type: 'value',
        gridIndex,
        min: -BREATH_PHASE_AXIS_EXTENT,
        max: BREATH_PHASE_AXIS_EXTENT,
        interval: BREATH_PHASE_AXIS_EXTENT * 2,
        axisLabel: {
          ...createLeftAxisLabelStyle(BREATH_AXIS_LABEL_FONT_SIZE),
          formatter: (value: number) => {
            if (value > 0) return t('monitoring.phase.inhale')
            if (value < 0) return t('monitoring.phase.exhale')
            return ''
          },
        },
      })
    }
  }

  // EEG panels
  let scoreGridIndex: number | null = null
  let bandsGridIndex: number | null = null
  let scoreYAxisIndex: number | null = null
  let bandsYAxisIndex: number | null = null

  if (hasEeg) {
    if (hasScoreData) {
      scoreGridIndex = gridOffset++
      scoreYAxisIndex = yAxis.length
      yAxis.push({
        type: 'value',
        gridIndex: scoreGridIndex,
        min: 0,
        max: 100,
        name: t('monitoring.axis.eegScore'),
        nameGap: LEFT_AXIS_NAME_GAP,
        nameTextStyle: createLeftAxisNameTextStyle(),
        axisLabel: createLeftAxisLabelStyle(),
      })
    }

    bandsGridIndex = gridOffset++
    bandsYAxisIndex = yAxis.length
    yAxis.push({
      type: 'log',
      gridIndex: bandsGridIndex,
      name: t('monitoring.axis.eegBands'),
      nameGap: LEFT_AXIS_NAME_GAP,
      nameTextStyle: createLeftAxisNameTextStyle(),
      axisLabel: createLeftAxisLabelStyle(),
      min: 1,
    })
  }

  return {
    panelIndexByName,
    yAxis,
    rrAxisIndex,
    scoreGridIndex,
    bandsGridIndex,
    scoreYAxisIndex,
    bandsYAxisIndex,
  }
}

// ─── Stacked mode ─────────────────────────────────────────────────────────────

function buildStackedEegOption(
  snapshot: LogChartDataSnapshot,
  panels: readonly LogChartPanel[],
  axisLayout: ChartAxisLayout,
  grid: GridComponentOption[],
  timeAxisLabelFormatter: (v: number | string) => string,
  timeAxisRotate: number,
  xAxisIndices: number[],
  zoomDefaults: object,
  breathAxisExtent: number,
  entries: readonly BuiltSeriesEntry[],
): MonitoringChartOption {
  const eegGridIndex = axisLayout.panelIndexByName.eeg
  if (eegGridIndex === null) {
    // No EEG panel — fall back
    return buildStandardOption(snapshot, panels, axisLayout, grid, timeAxisLabelFormatter, timeAxisRotate, xAxisIndices, zoomDefaults, breathAxisExtent, entries)
  }

  const combinedBands = combineEegBands(snapshot.series)
  const normalizedBands = normalizeBandsByTimestamp(combinedBands)

  // Build stacked area series for each band
  const stackedEntries: BuiltSeriesEntry[] = normalizedBands.map((band) => ({
    defaultVisible: true,
    option: {
      type: 'line' as const,
      name: t(`monitoring.series.${band.key}`),
      data: band.points.map((p) => [p[0], p[1]]),
      animation: false,
      xAxisIndex: eegGridIndex,
      yAxisIndex: axisLayout.valueAxisIndexByPanel.eeg ?? 0,
      stack: 'eeg',
      areaStyle: { color: combinedBandColor[band.key], opacity: 0.75 },
      lineStyle: { color: combinedBandColor[band.key], width: 0 },
      itemStyle: { color: combinedBandColor[band.key] },
      showSymbol: false,
      connectNulls: true,
      emphasis: { focus: 'series' as const },
    } satisfies LineSeriesOption,
  }))

  // Right axis for attention/meditation
  const eegYAxisBase = axisLayout.valueAxisIndexByPanel.eeg ?? 0
  const scoreYAxisIndex = eegYAxisBase + 1 // right axis added after
  const scoreSeries = snapshot.series.filter((s) => (s.key === 'attention' || s.key === 'meditation') && s.points.length > 0)
  const scoreEntries: BuiltSeriesEntry[] = scoreSeries.map((item) => ({
    defaultVisible: item.defaultVisible,
    option: {
      type: 'line' as const,
      name: labelForSeries(item.key),
      data: item.points.map((p) => [p[0], p[1]]),
      animation: false,
      xAxisIndex: eegGridIndex,
      yAxisIndex: scoreYAxisIndex,
      showSymbol: false,
      connectNulls: true,
      sampling: 'lttb',
      lineStyle: { color: seriesColorByKey[item.key], width: 2 },
      itemStyle: { color: seriesColorByKey[item.key] },
      emphasis: { focus: 'series' as const },
    } satisfies LineSeriesOption,
  }))

  const yAxisWithScore = [
    ...buildAxisLayout(panels).yAxis.map((axis, idx) => {
      if (idx === axisLayout.valueAxisIndexByPanel.eeg) {
        return {
          ...axis,
          type: 'value' as const,
          min: 0,
          max: 100,
          name: t('monitoring.axis.eegPct'),
          nameGap: LEFT_AXIS_NAME_GAP,
          nameTextStyle: createLeftAxisNameTextStyle(),
          axisLabel: createLeftAxisLabelStyle(),
          scale: false,
        }
      }
      return axis
    }),
    {
      type: 'value' as const,
      gridIndex: eegGridIndex,
      min: 0,
      max: 100,
      position: 'right' as const,
      name: t('monitoring.axis.eegScore'),
      axisLabel: createLeftAxisLabelStyle(),
    },
  ]

  const allStackedEntries = [...entries.filter((e) => {
    const name = String(e.option.name)
    // Exclude EEG series from the standard entries since we're replacing them
    const eegNames = [...EEG_BAND_KEYS, 'attention', 'meditation', 'raw', 'poorSignal'].map((k) => labelForSeries(k as LogChartSeriesKey))
    return !eegNames.includes(name)
  }), ...stackedEntries, ...scoreEntries]

  const legendEntries = allStackedEntries
  const graphic = [
    ...buildChartGraphics(axisLayout, grid),
    buildPoorSignalBadge(snapshot, chartRoot.value?.clientWidth ?? 960, chartRoot.value?.clientHeight ?? 520),
  ]

  return {
    animation: false,
    legend: {
      type: 'scroll',
      top: 0,
      left: 0,
      right: 0,
      selected: createLegendSelection(legendEntries),
    },
    tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } },
    axisPointer: { link: [{ xAxisIndex: xAxisIndices }] },
    graphic,
    grid,
    xAxis: buildTimeXAxis(panels, timeAxisLabelFormatter, timeAxisRotate),
    yAxis: yAxisWithScore as MonitoringChartOption['yAxis'],
    dataZoom: buildDataZoom(xAxisIndices, zoomDefaults),
    series: allStackedEntries.map((e) => e.option),
  }
}

// ─── Heatmap mode ─────────────────────────────────────────────────────────────

function buildHeatmapEegOption(
  snapshot: LogChartDataSnapshot,
  panels: readonly LogChartPanel[],
  axisLayout: ChartAxisLayout,
  grid: GridComponentOption[],
  timeAxisLabelFormatter: (v: number | string) => string,
  timeAxisRotate: number,
  xAxisIndices: number[],
  zoomDefaults: object,
  breathAxisExtent: number,
  entries: readonly BuiltSeriesEntry[],
): MonitoringChartOption {
  const eegGridIndex = axisLayout.panelIndexByName.eeg

  if (eegGridIndex === null) {
    return buildStandardOption(snapshot, panels, axisLayout, grid, timeAxisLabelFormatter, timeAxisRotate, xAxisIndices, zoomDefaults, breathAxisExtent, entries)
  }

  const combinedBands = combineEegBands(snapshot.series)
  const normalizedBands = normalizeBandsByTimestamp(combinedBands)

  // Build heatmap data: [timestamp, bandIndex, value]
  const bandLabels = COMBINED_BAND_KEYS.map((k) => t(`monitoring.series.${k}`))
  const heatmapData: [number, number, number][] = []

  normalizedBands.forEach((band, bandIdx) => {
    for (const point of band.points) {
      heatmapData.push([point[0], bandIdx, Math.round(point[1] * 10) / 10])
    }
  })

  // Standard non-EEG series
  const nonEegEntries = entries.filter((e) => {
    const eegNames = [...EEG_BAND_KEYS, 'attention', 'meditation', 'raw', 'poorSignal'].map((k) => labelForSeries(k as LogChartSeriesKey))
    return !eegNames.includes(String(e.option.name))
  })

  // Replace EEG y-axis with categorical
  const yAxisWithHeatmap = buildAxisLayout(panels).yAxis.map((axis, idx) => {
    if (idx === axisLayout.valueAxisIndexByPanel.eeg) {
      return {
        type: 'category' as const,
        gridIndex: eegGridIndex,
        data: bandLabels,
        axisLabel: { ...createLeftAxisLabelStyle(), fontSize: 10 },
      }
    }
    return axis
  })

  const heatmapSeries: HeatmapSeriesOption = {
    type: 'heatmap',
    name: t('monitoring.axis.eegBands'),
    data: heatmapData,
    xAxisIndex: eegGridIndex,
    yAxisIndex: axisLayout.valueAxisIndexByPanel.eeg ?? 0,
    animation: false,
  }

  const graphic = [
    ...buildChartGraphics(axisLayout, grid),
    buildPoorSignalBadge(snapshot, chartRoot.value?.clientWidth ?? 960, chartRoot.value?.clientHeight ?? 520),
  ]

  return {
    animation: false,
    legend: {
      type: 'scroll',
      top: 0,
      left: 0,
      right: 0,
      selected: createLegendSelection(nonEegEntries),
    },
    tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } },
    axisPointer: { link: [{ xAxisIndex: xAxisIndices }] },
    graphic,
    grid,
    xAxis: buildTimeXAxis(panels, timeAxisLabelFormatter, timeAxisRotate),
    yAxis: yAxisWithHeatmap,
    visualMap: [{
      type: 'continuous',
      min: 0,
      max: 100,
      calculable: true,
      orient: 'horizontal',
      left: 'center',
      bottom: CHART_GRID_BOTTOM + 24,
      itemHeight: 120,
      itemWidth: 10,
      text: ['100%', '0%'],
      inRange: {
        color: ['#0a1628', '#1565c0', '#0097a7', '#43aa8b', '#f9c74f'],
      },
      textStyle: { color: TIME_AXIS_LABEL_COLOR, fontSize: 10 },
      show: true,
    }],
    dataZoom: buildDataZoom(xAxisIndices, zoomDefaults),
    series: [...nonEegEntries.map((e) => e.option), heatmapSeries],
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

function buildTimeXAxis(panels: readonly LogChartPanel[], timeAxisLabelFormatter: (v: number | string) => string, timeAxisRotate: number) {
  return panels.map((_, index) => {
    if (index !== panels.length - 1) {
      return {
        type: 'time' as const,
        gridIndex: index,
        axisLabel: { show: false },
        axisTick: { show: false },
        axisLine: { show: false },
      }
    }
    return {
      type: 'time' as const,
      gridIndex: index,
      axisLine: { show: true, lineStyle: { color: TIME_AXIS_LINE_COLOR } },
      axisTick: { show: true, length: TIME_AXIS_TICK_LENGTH, lineStyle: { color: TIME_AXIS_LINE_COLOR } },
      axisLabel: {
        show: true,
        color: TIME_AXIS_LABEL_COLOR,
        fontSize: TIME_AXIS_LABEL_FONT_SIZE,
        hideOverlap: true,
        showMinLabel: true,
        showMaxLabel: true,
        margin: TIME_AXIS_LABEL_MARGIN,
        rotate: timeAxisRotate,
        formatter: timeAxisLabelFormatter,
      },
    }
  })
}

function buildDataZoom(xAxisIndices: number[], zoomDefaults: object): DataZoomComponentOption[] {
  return [
    { type: 'inside', xAxisIndex: xAxisIndices, filterMode: 'none', ...zoomDefaults },
    { type: 'slider', xAxisIndex: xAxisIndices, height: 18, bottom: 4, filterMode: 'none', ...zoomDefaults },
  ]
}

function buildStandardOption(
  snapshot: LogChartDataSnapshot,
  panels: readonly LogChartPanel[],
  axisLayout: ChartAxisLayout,
  grid: GridComponentOption[],
  timeAxisLabelFormatter: (v: number | string) => string,
  timeAxisRotate: number,
  xAxisIndices: number[],
  zoomDefaults: object,
  breathAxisExtent: number,
  entries: readonly BuiltSeriesEntry[],
  yAxisOverride?: MonitoringChartOption['yAxis'],
): MonitoringChartOption {
  const graphic = [
    ...buildChartGraphics(axisLayout, grid),
    buildPoorSignalBadge(snapshot, chartRoot.value?.clientWidth ?? 960, chartRoot.value?.clientHeight ?? 520),
  ]

  const yAxis = yAxisOverride ?? buildAxisLayout(panels).yAxis.map((axis, index) => {
    if (axisLayout.valueAxisIndexByPanel.breath !== index) return axis
    return { ...axis, min: -breathAxisExtent, max: breathAxisExtent, interval: breathAxisExtent * 2 }
  })

  return {
    animation: false,
    legend: {
      type: 'scroll',
      top: 0,
      left: 0,
      right: 0,
      selected: createLegendSelection(entries),
    },
    tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } },
    axisPointer: { link: [{ xAxisIndex: xAxisIndices }] },
    graphic,
    grid,
    xAxis: buildTimeXAxis(panels, timeAxisLabelFormatter, timeAxisRotate),
    yAxis,
    dataZoom: buildDataZoom(xAxisIndices, zoomDefaults),
    series: entries.map((e) => e.option),
  }
}

function getGridLayoutKey(panels: readonly LogChartPanel[]): ChartGridLayoutKey {
  return panels.join('-') as ChartGridLayoutKey
}

function buildGridLayout(panels: readonly LogChartPanel[]): GridComponentOption[] {
  const layout = GRID_LAYOUT_BY_KEY[getGridLayoutKey(panels)]
  return layout.map((gridItem) => ({ ...gridItem }))
}

function resolvePixelValue(value: number | string | undefined, total: number): number {
  if (typeof value === 'number') {
    return value
  }

  if (typeof value === 'string' && value.endsWith('%')) {
    const percentValue = Number.parseFloat(value.slice(0, -1))
    return Number.isFinite(percentValue) ? total * percentValue / 100 : 0
  }

  return 0
}

function resolveGridHeightPx(gridConfig: GridComponentOption, totalHeight: number): number {
  if (gridConfig.height !== undefined) {
    return resolvePixelValue(gridConfig.height, totalHeight)
  }

  const top = resolvePixelValue(gridConfig.top, totalHeight)
  const bottom = resolvePixelValue(gridConfig.bottom, totalHeight)
  return Math.max(0, totalHeight - top - bottom)
}

function resolveGridTopPx(gridConfig: GridComponentOption, totalHeight: number): number {
  if (gridConfig.top !== undefined) {
    return resolvePixelValue(gridConfig.top, totalHeight)
  }

  const bottom = resolvePixelValue(gridConfig.bottom, totalHeight)
  const height = resolveGridHeightPx(gridConfig, totalHeight)
  return Math.max(0, totalHeight - bottom - height)
}

function resolveBottomAxisLineY(grid: readonly GridComponentOption[]): number {
  const chartHeight = chartRoot.value?.clientHeight ?? 520
  const lastGrid = grid.at(-1)
  if (lastGrid === undefined) {
    return chartHeight - CHART_GRID_BOTTOM
  }

  return chartHeight - resolvePixelValue(lastGrid.bottom, chartHeight)
}

function buildTimeAxisGraphic(grid: readonly GridComponentOption[]): GraphicComponentOption | null {
  const chartWidth = chartRoot.value?.clientWidth ?? 960
  const axisLineY = resolveBottomAxisLineY(grid)
  const top = axisLineY - TIME_AXIS_LABEL_FONT_SIZE / 2 + TIME_AXIS_GRAPHIC_VERTICAL_OFFSET

  return {
    type: 'text',
    left: chartWidth - CHART_GRID_RIGHT + TIME_AXIS_GRAPHIC_RIGHT_GAP,
    top,
    silent: true,
    style: {
      text: t('monitoring.axis.time'),
      fill: TIME_AXIS_LABEL_COLOR,
      fontSize: TIME_AXIS_LABEL_FONT_SIZE,
      align: 'left',
      verticalAlign: 'top',
    },
  }
}

function resolveBreathAxisExtent(axisLayout: ChartAxisLayout, grid: readonly GridComponentOption[]): number {
  const breathGridIndex = axisLayout.panelIndexByName.breath
  if (breathGridIndex === null) {
    return BREATH_PHASE_AXIS_EXTENT
  }

  const breathGrid = grid[breathGridIndex]
  if (breathGrid === undefined) {
    return BREATH_PHASE_AXIS_EXTENT
  }

  const chartHeight = chartRoot.value?.clientHeight ?? 520
  const panelHeight = resolveGridHeightPx(breathGrid, chartHeight)
  if (panelHeight <= 0) {
    return BREATH_PHASE_AXIS_EXTENT
  }

  const targetPaddingPx = Math.min(BREATH_AXIS_TARGET_PADDING_PX, Math.max(0, panelHeight / 2 - 1))
  const denominator = 1 - (targetPaddingPx * 2 / panelHeight)
  if (denominator <= 0.01) {
    return BREATH_PHASE_AXIS_EXTENT
  }

  return Math.max(BREATH_PHASE_VISUAL_SCALE + 0.01, BREATH_PHASE_VISUAL_SCALE / denominator)
}

function buildPanelTitleGraphic(
  panel: LogChartPanel,
  axisLayout: ChartAxisLayout,
  grid: readonly GridComponentOption[],
): GraphicComponentOption | null {
  const gridIndex = axisLayout.panelIndexByName[panel]
  if (gridIndex === null) {
    return null
  }

  const gridConfig = grid[gridIndex]
  if (gridConfig === undefined) {
    return null
  }

  const chartWidth = chartRoot.value?.clientWidth ?? 960
  const chartHeight = chartRoot.value?.clientHeight ?? 520
  const text = panel === 'ecg'
    ? t('monitoring.axis.hr')
    : panel === 'breath'
      ? t('monitoring.axis.breath')
      : t('monitoring.axis.eeg')
  const fontSize = panel === 'breath' ? BREATH_AXIS_LABEL_FONT_SIZE : 12
  const left = resolvePixelValue(gridConfig.left, chartWidth) + PANEL_TITLE_LEFT_OFFSET
  const top = Math.max(0, resolveGridTopPx(gridConfig, chartHeight) - fontSize - PANEL_TITLE_TOP_GAP)

  return {
    type: 'text',
    left,
    top,
    silent: true,
    style: {
      text,
      fill: TIME_AXIS_LABEL_COLOR,
      fontSize,
      align: 'left',
      verticalAlign: 'top',
    },
  }
}

function buildChartGraphics(axisLayout: ChartAxisLayout, grid: readonly GridComponentOption[]): GraphicComponentOption[] {
  return [
    buildPanelTitleGraphic('ecg', axisLayout, grid),
    buildPanelTitleGraphic('breath', axisLayout, grid),
    buildTimeAxisGraphic(grid),
  ].filter((item): item is GraphicComponentOption => item !== null)
}

function createLeftAxisNameTextStyle(fontSize = 12) {
  return {
    fontSize,
    align: 'right' as const,
  }
}

function createLeftAxisLabelStyle(fontSize = 12) {
  return {
    align: 'right' as const,
    fontSize,
    margin: LEFT_AXIS_LABEL_MARGIN,
  }
}

function buildAxisLayout(panels: readonly LogChartPanel[]) {
  const panelIndexByName: Record<LogChartPanel, number | null> = {
    ecg: null,
    breath: null,
    eeg: null,
  }

  panels.forEach((panel, index) => {
    panelIndexByName[panel] = index
  })

  const valueAxisIndexByPanel: Record<LogChartPanel, number | null> = {
    ecg: null,
    breath: null,
    eeg: null,
  }

  let rrAxisIndex: number | null = null
  const yAxis: MonitoringChartOption['yAxis'] = []

  for (const panel of panels) {
    const gridIndex = panelIndexByName[panel] ?? 0

    if (panel === 'ecg') {
      valueAxisIndexByPanel.ecg = yAxis.length
      yAxis.push({
        type: 'value',
        gridIndex,
        axisLabel: createLeftAxisLabelStyle(),
        scale: true,
      })

      rrAxisIndex = yAxis.length
      yAxis.push({
        type: 'value',
        gridIndex,
        name: t('monitoring.axis.rr'),
        position: 'right',
        scale: true,
      })
      continue
    }

    if (panel === 'breath') {
      valueAxisIndexByPanel.breath = yAxis.length
      yAxis.push({
        type: 'value',
        gridIndex,
        min: -BREATH_PHASE_AXIS_EXTENT,
        max: BREATH_PHASE_AXIS_EXTENT,
        interval: BREATH_PHASE_AXIS_EXTENT * 2,
        axisLabel: {
          ...createLeftAxisLabelStyle(BREATH_AXIS_LABEL_FONT_SIZE),
          formatter: (value: number) => {
            if (value > 0) {
              return t('monitoring.phase.inhale')
            }

            if (value < 0) {
              return t('monitoring.phase.exhale')
            }

            return ''
          },
        },
      })
      continue
    }

    valueAxisIndexByPanel.eeg = yAxis.length
    yAxis.push({
      type: 'value',
      gridIndex,
      name: t('monitoring.axis.eeg'),
      nameGap: LEFT_AXIS_NAME_GAP,
      nameTextStyle: createLeftAxisNameTextStyle(),
      axisLabel: createLeftAxisLabelStyle(),
      scale: true,
    })
  }

  return {
    layout: {
      panelIndexByName,
      valueAxisIndexByPanel,
      rrAxisIndex,
    } satisfies ChartAxisLayout,
    yAxis,
  }
}

function createBreathSeries(item: LogChartSeries, axisLayout: ChartAxisLayout): readonly BuiltSeriesEntry[] {
  const xAxisIndex = axisLayout.panelIndexByName.breath ?? 0
  const yAxisIndex = axisLayout.valueAxisIndexByPanel.breath ?? 0
  const base = {
    type: 'line' as const,
    animation: false,
    xAxisIndex,
    yAxisIndex,
    showSymbol: false,
    connectNulls: false,
    step: 'end' as const,
    emphasis: {
      focus: 'series' as const,
    },
  }

  return [
    {
      defaultVisible: item.defaultVisible,
      option: {
        ...base,
        name: t('monitoring.phase.inhale'),
        data: item.points.map((point) => [point[0], point[1] > 0 ? BREATH_PHASE_VISUAL_SCALE : null]),
        lineStyle: {
          color: BREATH_PHASE_COLORS.inhale.line,
          width: 2,
        },
        areaStyle: {
          color: BREATH_PHASE_COLORS.inhale.area,
        },
      },
    },
    {
      defaultVisible: item.defaultVisible,
      option: {
        ...base,
        name: t('monitoring.phase.exhale'),
        data: item.points.map((point) => [point[0], point[1] < 0 ? -BREATH_PHASE_VISUAL_SCALE : null]),
        lineStyle: {
          color: BREATH_PHASE_COLORS.exhale.line,
          width: 2,
        },
        areaStyle: {
          color: BREATH_PHASE_COLORS.exhale.area,
        },
      },
    },
  ]
}

function buildSeriesEntries(item: LogChartSeries, axisLayout: ChartAxisLayout): readonly BuiltSeriesEntry[] {
  if (item.key === 'breath_phase') {
    return createBreathSeries(item, axisLayout)
  }

  const name = labelForSeries(item.key)
  const data = item.points.map((point) => [point[0], point[1]])
  const xAxisIndex = axisLayout.panelIndexByName[item.panel] ?? 0
  const yAxisIndex = item.key === 'rr'
    ? axisLayout.rrAxisIndex ?? axisLayout.valueAxisIndexByPanel.ecg ?? 0
    : axisLayout.valueAxisIndexByPanel[item.panel] ?? 0
  const common = {
    name,
    data,
    animation: false,
    xAxisIndex,
    yAxisIndex,
    itemStyle: {
      color: seriesColorByKey[item.key],
    },
    lineStyle: {
      color: seriesColorByKey[item.key],
      width: ECG_SERIES_STROKE_WIDTH,
    },
    emphasis: {
      focus: 'series' as const,
    },
  }

  if (item.renderMode === 'scatter') {
    return [{
      defaultVisible: item.defaultVisible,
      option: {
        ...common,
        type: 'scatter',
        symbolSize: RR_SYMBOL_SIZE,
      },
    }]
  }

  return [{
    defaultVisible: item.defaultVisible && item.key !== 'raw' && item.key !== 'poorSignal',
    option: {
      ...common,
      type: 'line',
      showSymbol: false,
      connectNulls: true,
      sampling: 'lttb',
      step: item.renderMode === 'step' ? 'end' : undefined,
    },
  }]
}

function buildOption(snapshot: LogChartDataSnapshot, includeViewportDefaults: boolean): MonitoringChartOption {
  const eegMode = props.eegMode ?? 'lines'

  // Radar mode: exclude EEG panels — caller (MonitoringPage) renders EegRadarChart instead
  const allPanels = resolveVisiblePanels(snapshot)
  const panels = eegMode === 'radar' ? allPanels.filter((p) => p !== 'eeg') : allPanels
  const effectivePanels = panels.length > 0 ? panels : ['ecg' as const]

  const xAxisIndices = effectivePanels.map((_, index) => index)
  const timeRangeMs = getTimeRangeMs(snapshot)
  const timeAxisLabelFormatter = createTimeAxisLabelFormatter(timeRangeMs, locale.value)
  const timeAxisRotate = timeRangeMs !== null && timeRangeMs >= TIME_AXIS_ROTATE_WINDOW_MS ? 30 : 0
  const zoomDefaults = includeViewportDefaults ? resolveZoomDefaults(snapshot, props.viewportPreset) : {}

  if (eegMode === 'subpanels' && effectivePanels.includes('eeg')) {
    const hasScoreData = snapshot.series.some(
      (s) => (s.key === 'attention' || s.key === 'meditation') && s.points.length > 0,
    )
    const grid = buildSubpanelGridLayout(effectivePanels, hasScoreData)
    const spLayout = buildSubpanelsAxisLayout(effectivePanels, hasScoreData)
    const nonEegCount = effectivePanels.filter((p) => p !== 'eeg').length

    const allSeries: ChartSeriesOption[] = []

    // Standard non-EEG series
    const fakeAxisLayout: ChartAxisLayout = {
      panelIndexByName: spLayout.panelIndexByName,
      valueAxisIndexByPanel: {
        ecg: spLayout.panelIndexByName.ecg !== null ? 0 : null,
        breath: spLayout.panelIndexByName.breath !== null ? (spLayout.panelIndexByName.ecg !== null ? 2 : 0) : null,
        eeg: null, // handled separately
      },
      rrAxisIndex: spLayout.rrAxisIndex,
    }

    for (const item of snapshot.series) {
      if (item.points.length === 0) continue
      if (item.panel === 'eeg') continue
      const built = buildSeriesEntries(item, fakeAxisLayout)
      allSeries.push(...built.map((e) => e.option))
    }

    // Score series (attention/meditation)
    if (hasScoreData && spLayout.scoreGridIndex !== null && spLayout.scoreYAxisIndex !== null) {
      for (const item of snapshot.series) {
        if (item.points.length === 0) continue
        if (item.key !== 'attention' && item.key !== 'meditation') continue
        allSeries.push({
          type: 'line',
          name: labelForSeries(item.key),
          data: item.points.map((p) => [p[0], p[1]]),
          animation: false,
          xAxisIndex: spLayout.scoreGridIndex,
          yAxisIndex: spLayout.scoreYAxisIndex,
          showSymbol: false,
          connectNulls: true,
          sampling: 'lttb',
          lineStyle: { color: seriesColorByKey[item.key], width: 1.5 },
          itemStyle: { color: seriesColorByKey[item.key] },
          emphasis: { focus: 'series' },
        } satisfies LineSeriesOption)
      }
    }

    // Band series (log scale)
    if (spLayout.bandsGridIndex !== null && spLayout.bandsYAxisIndex !== null) {
      for (const item of snapshot.series) {
        if (item.points.length === 0) continue
        if (!(EEG_BAND_KEYS as readonly string[]).includes(item.key)) continue
        allSeries.push({
          type: 'line',
          name: labelForSeries(item.key),
          data: item.points.map((p) => [p[0], Math.max(1, p[1])]),
          animation: false,
          xAxisIndex: spLayout.bandsGridIndex,
          yAxisIndex: spLayout.bandsYAxisIndex,
          showSymbol: false,
          connectNulls: true,
          sampling: 'lttb',
          lineStyle: { color: seriesColorByKey[item.key], width: 1.5 },
          itemStyle: { color: seriesColorByKey[item.key] },
          emphasis: { focus: 'series' },
        } satisfies LineSeriesOption)
      }
    }

    // Build all xAxis (one per grid)
    const allGridCount = grid.length
    const xAxisList = Array.from({ length: allGridCount }, (_, i) => {
      const isLast = i === allGridCount - 1
      if (!isLast) {
        return { type: 'time' as const, gridIndex: i, axisLabel: { show: false }, axisTick: { show: false }, axisLine: { show: false } }
      }
      return {
        type: 'time' as const,
        gridIndex: i,
        axisLine: { show: true, lineStyle: { color: TIME_AXIS_LINE_COLOR } },
        axisTick: { show: true, length: TIME_AXIS_TICK_LENGTH, lineStyle: { color: TIME_AXIS_LINE_COLOR } },
        axisLabel: {
          show: true,
          color: TIME_AXIS_LABEL_COLOR,
          fontSize: TIME_AXIS_LABEL_FONT_SIZE,
          hideOverlap: true,
          showMinLabel: true,
          showMaxLabel: true,
          margin: TIME_AXIS_LABEL_MARGIN,
          rotate: timeAxisRotate,
          formatter: timeAxisLabelFormatter,
        },
      }
    })

    const allXAxisIndices = Array.from({ length: allGridCount }, (_, i) => i)

    const dummyEntries: BuiltSeriesEntry[] = allSeries.map((s) => ({
      option: s,
      defaultVisible: true,
    }))

    const graphic = [
      buildPoorSignalBadge(snapshot, chartRoot.value?.clientWidth ?? 960, chartRoot.value?.clientHeight ?? 520),
    ]

    return {
      animation: false,
      legend: { type: 'scroll', top: 0, left: 0, right: 0, selected: createLegendSelection(dummyEntries) },
      tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } },
      axisPointer: { link: [{ xAxisIndex: allXAxisIndices }] },
      graphic,
      grid,
      xAxis: xAxisList,
      yAxis: spLayout.yAxis,
      dataZoom: buildDataZoom(allXAxisIndices, zoomDefaults),
      series: allSeries,
    }
  }

  const grid = buildGridLayout(effectivePanels)
  const { layout: axisLayout, yAxis } = buildAxisLayout(effectivePanels)
  const breathAxisExtent = resolveBreathAxisExtent(axisLayout, grid)
  const entries = snapshot.series
    .filter((item) => item.points.length > 0 && (eegMode !== 'radar' || item.panel !== 'eeg'))
    .flatMap((item) => buildSeriesEntries(item, axisLayout))

  if (eegMode === 'stacked') {
    return buildStackedEegOption(snapshot, effectivePanels, axisLayout, grid, timeAxisLabelFormatter, timeAxisRotate, xAxisIndices, zoomDefaults, breathAxisExtent, entries)
  }

  if (eegMode === 'heatmap') {
    return buildHeatmapEegOption(snapshot, effectivePanels, axisLayout, grid, timeAxisLabelFormatter, timeAxisRotate, xAxisIndices, zoomDefaults, breathAxisExtent, entries)
  }

  // lines or radar (radar: EEG excluded from panels above)
  const breathYAxis = yAxis.map((axis, index) => {
    if (axisLayout.valueAxisIndexByPanel.breath !== index) return axis
    return { ...axis, min: -breathAxisExtent, max: breathAxisExtent, interval: breathAxisExtent * 2 }
  })
  return buildStandardOption(snapshot, effectivePanels, axisLayout, grid, timeAxisLabelFormatter, timeAxisRotate, xAxisIndices, zoomDefaults, breathAxisExtent, entries, breathYAxis)
}

function renderChart(includeViewportDefaults = false) {
  if (chartInstance === null) {
    return
  }

  chartInstance.setOption(buildOption(props.data, includeViewportDefaults), {
    notMerge: false,
    lazyUpdate: true,
    replaceMerge: ['graphic', 'grid', 'xAxis', 'yAxis', 'dataZoom', 'series'],
  })
}

onMounted(() => {
  if (chartRoot.value === null) {
    return
  }

  chartInstance = init(chartRoot.value, undefined, { renderer: 'canvas' })
  lastPointCount = getPointCount(props.data)
  renderChart(true)

  chartInstance.on('legendselectchanged', (event: unknown) => {
    if (typeof event !== 'object' || event === null || !('selected' in event)) {
      return
    }

    const { selected } = event as { selected?: Record<string, boolean> }
    if (selected !== undefined) {
      legendSelection.value = { ...selected }
    }
  })

  resizeObserver = new ResizeObserver(() => {
    chartInstance?.resize()
    renderChart()
  })
  resizeObserver.observe(chartRoot.value)
})

watch(() => props.data, () => {
  const pointCount = getPointCount(props.data)
  const shouldResetViewport = lastPointCount === 0 && pointCount > 0
  lastPointCount = pointCount
  renderChart(shouldResetViewport)
})

watch(() => props.mode, () => {
  legendSelection.value = null
  lastPointCount = getPointCount(props.data)
  renderChart(true)
})

watch(() => props.eegMode, () => {
  legendSelection.value = null
  renderChart(true)
})

watch(() => props.viewportToken, () => {
  renderChart(true)
})

watch(() => locale.value, () => {
  legendSelection.value = null
  renderChart(true)
})

onBeforeUnmount(() => {
  resizeObserver?.disconnect()
  resizeObserver = null
  chartInstance?.dispose()
  chartInstance = null
})
</script>

<style scoped>
.device-data-chart {
  width: 100%;
  height: 100%;
  min-height: 520px;
}

@media (max-width: 1023px) {
  .device-data-chart {
    min-height: 460px;
  }
}

@media (max-width: 599px) {
  .device-data-chart {
    min-height: 420px;
  }
}
</style>