<template>
  <div ref="chartRoot" class="device-data-chart" />
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { use, init, type ComposeOption, type ECharts } from 'echarts/core'
import { LineChart, ScatterChart, type LineSeriesOption, type ScatterSeriesOption } from 'echarts/charts'
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  DataZoomComponent,
  GraphicComponent,
  type GridComponentOption,
  type TooltipComponentOption,
  type LegendComponentOption,
  type DataZoomComponentOption,
  type GraphicComponentOption,
} from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { LogChartDataSnapshot, LogChartPanel, LogChartSeries, LogChartSeriesKey } from '@protocol'
import type { EegDisplayMode } from '../stores/preferences'
import {
  EEG_BAND_COLORS,
} from '../services/eeg-band-colors'

use([LineChart, ScatterChart, GridComponent, TooltipComponent, LegendComponent, DataZoomComponent, GraphicComponent, CanvasRenderer])

type MonitoringChartOption = ComposeOption<
  | LineSeriesOption
  | ScatterSeriesOption
  | GridComponentOption
  | TooltipComponentOption
  | LegendComponentOption
  | DataZoomComponentOption
  | GraphicComponentOption
>

type ChartSeriesOption = LineSeriesOption | ScatterSeriesOption
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
  eegMode: 'bands',
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
  ...EEG_BAND_COLORS,
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
  const eegMode = props.eegMode

  // Radar mode: exclude EEG panels — caller (MonitoringPage) renders EegRadarChart instead
  const allPanels = resolveVisiblePanels(snapshot)
  const panels = eegMode === 'radar' ? allPanels.filter((p) => p !== 'eeg') : allPanels
  const effectivePanels = panels.length > 0 ? panels : ['ecg' as const]

  const xAxisIndices = effectivePanels.map((_, index) => index)
  const timeRangeMs = getTimeRangeMs(snapshot)
  const timeAxisLabelFormatter = createTimeAxisLabelFormatter(timeRangeMs, locale.value)
  const timeAxisRotate = timeRangeMs !== null && timeRangeMs >= TIME_AXIS_ROTATE_WINDOW_MS ? 30 : 0
  const zoomDefaults = includeViewportDefaults ? resolveZoomDefaults(snapshot, props.viewportPreset) : {}

  const grid = buildGridLayout(effectivePanels)
  const { layout: axisLayout, yAxis } = buildAxisLayout(effectivePanels)
  const breathAxisExtent = resolveBreathAxisExtent(axisLayout, grid)
  const entries = snapshot.series
    .filter((item) => item.points.length > 0 && (eegMode !== 'radar' || item.panel !== 'eeg'))
    .flatMap((item) => buildSeriesEntries(item, axisLayout))

  // bands or radar (radar: EEG excluded from panels above)
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