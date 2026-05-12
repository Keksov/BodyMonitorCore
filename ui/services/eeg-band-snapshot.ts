import type { LogChartDataSnapshot, LogChartSeriesKey } from '@protocol'

export const EEG_BAND_KEYS = [
  'delta',
  'theta',
  'alpha1',
  'alpha2',
  'beta1',
  'beta2',
  'gamma1',
  'gamma2',
] as const

export type EegBandKey = (typeof EEG_BAND_KEYS)[number]

export type EegBandValues = Record<EegBandKey, number>

export interface EegBandAveragesSnapshot {
  readonly anchorTimestampMs: number
  readonly bandValues: EegBandValues
  readonly sampleCounts: Record<EegBandKey, number>
}

export const ALGO_BP_KEYS = [
  'bpDelta',
  'bpTheta',
  'bpAlpha',
  'bpBeta',
  'bpGamma',
] as const

export type AlgoBpKey = (typeof ALGO_BP_KEYS)[number]

export type AlgoBpValues = Record<AlgoBpKey, number>

export interface AlgoBpSnapshot {
  readonly anchorTimestampMs: number
  readonly bandValues: AlgoBpValues
  readonly sampleCounts: Record<AlgoBpKey, number>
}

interface AverageWithCount {
  readonly value: number
  readonly count: number
}

const clamp01 = (value: number): number => {
  return Math.max(0, Math.min(1, value))
}

function getSeriesPoints(snapshot: LogChartDataSnapshot, key: LogChartSeriesKey): readonly [number, number][] {
  const series = snapshot.series.find((entry) => entry.key === key)
  return (series?.points ?? []) as readonly [number, number][]
}

export function resolveAnchorTimestampMs(
  snapshot: LogChartDataSnapshot,
  anchorTimestampMs?: number | null,
): number | null {
  return anchorTimestampMs ?? snapshot.maxTimestampMs
}

function getWindowAverage(
  points: readonly [number, number][],
  startTimestampMs: number,
  endTimestampMs: number,
): AverageWithCount {
  let count = 0
  let sum = 0

  for (const point of points) {
    if (point[0] < startTimestampMs || point[0] > endTimestampMs) {
      continue
    }

    count += 1
    sum += point[1]
  }

  if (count === 0) {
    return { value: 0, count: 0 }
  }

  return {
    value: sum / count,
    count,
  }
}

export function getLatestSeriesValue(
  snapshot: LogChartDataSnapshot,
  key: LogChartSeriesKey,
  anchorTimestampMs?: number | null,
): number | null {
  const anchorMs = resolveAnchorTimestampMs(snapshot, anchorTimestampMs)
  if (anchorMs === null) {
    return null
  }

  const points = getSeriesPoints(snapshot, key)
  for (let index = points.length - 1; index >= 0; index -= 1) {
    const [timestampMs, value] = points[index]
    if (timestampMs <= anchorMs) {
      return value
    }
  }

  return null
}

export function buildEegBandAveragesSnapshot(
  snapshot: LogChartDataSnapshot,
  windowSec: number,
  anchorTimestampMs?: number | null,
): EegBandAveragesSnapshot | null {
  const anchorMs = resolveAnchorTimestampMs(snapshot, anchorTimestampMs)
  if (anchorMs === null) {
    return null
  }

  const bandValues = {} as EegBandValues
  const sampleCounts = {} as Record<EegBandKey, number>

  if (windowSec === 0) {
    for (const bandKey of EEG_BAND_KEYS) {
      const latest = getLatestSeriesValue(snapshot, bandKey, anchorMs)
      if (latest !== null) {
        bandValues[bandKey] = latest
        sampleCounts[bandKey] = 1
      } else {
        bandValues[bandKey] = 0
        sampleCounts[bandKey] = 0
      }
    }
  } else {
    const normalizedWindowSec = Math.max(1, Math.trunc(windowSec))
    const startTimestampMs = anchorMs - normalizedWindowSec * 1000

    for (const bandKey of EEG_BAND_KEYS) {
      const average = getWindowAverage(getSeriesPoints(snapshot, bandKey), startTimestampMs, anchorMs)
      bandValues[bandKey] = average.value
      sampleCounts[bandKey] = average.count
    }
  }

  return {
    anchorTimestampMs: anchorMs,
    bandValues,
    sampleCounts,
  }
}

export function buildAlgoBpSnapshot(
  snapshot: LogChartDataSnapshot,
  windowSec: number,
  anchorTimestampMs?: number | null,
): AlgoBpSnapshot | null {
  const anchorMs = resolveAnchorTimestampMs(snapshot, anchorTimestampMs)
  if (anchorMs === null) {
    return null
  }

  const bandValues = {} as AlgoBpValues
  const sampleCounts = {} as Record<AlgoBpKey, number>

  if (windowSec === 0) {
    for (const bandKey of ALGO_BP_KEYS) {
      const latest = getLatestSeriesValue(snapshot, bandKey, anchorMs)
      if (latest !== null) {
        bandValues[bandKey] = latest
        sampleCounts[bandKey] = 1
      } else {
        bandValues[bandKey] = 0
        sampleCounts[bandKey] = 0
      }
    }
  } else {
    const normalizedWindowSec = Math.max(1, Math.trunc(windowSec))
    const startTimestampMs = anchorMs - normalizedWindowSec * 1000

    for (const bandKey of ALGO_BP_KEYS) {
      const average = getWindowAverage(getSeriesPoints(snapshot, bandKey), startTimestampMs, anchorMs)
      bandValues[bandKey] = average.value
      sampleCounts[bandKey] = average.count
    }
  }

  return {
    anchorTimestampMs: anchorMs,
    bandValues,
    sampleCounts,
  }
}

export function calibrateBandValues(
  rawBandValues: EegBandValues,
  bandMin: Record<EegBandKey, number>,
  bandMax: Record<EegBandKey, number>,
): EegBandValues {
  return Object.fromEntries(
    EEG_BAND_KEYS.map((bandKey) => {
      const minValue = bandMin[bandKey]
      const maxValue = bandMax[bandKey]
      if (!Number.isFinite(minValue) || !Number.isFinite(maxValue) || maxValue <= minValue) {
        return [bandKey, 0]
      }

      const normalizedValue = (rawBandValues[bandKey] - minValue) / (maxValue - minValue)
      return [bandKey, clamp01(normalizedValue) * 100]
    }),
  ) as EegBandValues
}
