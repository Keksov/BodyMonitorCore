import { defineStore } from 'pinia'
import { ref, watch } from 'vue'
import { COMBINED_EEG_BAND_COLORS, EEG_BAND_COLORS } from '../services/eeg-band-colors'
import { EEG_BAND_KEYS } from '../services/eeg-band-snapshot'

export type EegSignalLineType = 'solid' | 'dashed' | 'dotted' | 'twodash' | 'longdash' | 'dotdash'

export interface EegSignalStyle {
  readonly color: string
  readonly lineType: EegSignalLineType
  readonly glowIntensity: number
}

const STORAGE_KEY = 'eeg-signal-style-map'
const VALID_LINE_TYPES: readonly EegSignalLineType[] = [
  'solid',
  'dashed',
  'dotted',
  'twodash',
  'longdash',
  'dotdash',
]
const FALLBACK_COLOR = '#60a5fa'
const FALLBACK_STYLE: EegSignalStyle = {
  color: FALLBACK_COLOR,
  lineType: 'solid',
  glowIntensity: 0,
}

const DEFAULT_SIGNAL_COLORS: Record<string, string> = {
  attention: '#2a9d8f',
  meditation: '#457b9d',
  poorSignal: '#9aa5b1',
  bpDelta: COMBINED_EEG_BAND_COLORS.delta,
  bpTheta: COMBINED_EEG_BAND_COLORS.theta,
  bpAlpha: COMBINED_EEG_BAND_COLORS.alpha,
  bpBeta: COMBINED_EEG_BAND_COLORS.beta,
  bpGamma: COMBINED_EEG_BAND_COLORS.gamma,
}

for (const bandKey of EEG_BAND_KEYS) {
  DEFAULT_SIGNAL_COLORS[bandKey] = EEG_BAND_COLORS[bandKey]
}

function normalizeColorHex(value: unknown, fallbackColor: string): string {
  if (typeof value !== 'string') {
    return fallbackColor
  }

  const trimmed = value.trim()
  const longHexMatch = /^#[0-9a-fA-F]{6}$/.exec(trimmed)
  if (longHexMatch !== null) {
    return trimmed.toLowerCase()
  }

  const shortHexMatch = /^#[0-9a-fA-F]{3}$/.exec(trimmed)
  if (shortHexMatch !== null) {
    const [r, g, b] = trimmed.slice(1)
    return `#${r}${r}${g}${g}${b}${b}`.toLowerCase()
  }

  return fallbackColor
}

function normalizeLineType(value: unknown): EegSignalLineType {
  if (typeof value === 'string' && (VALID_LINE_TYPES as readonly string[]).includes(value)) {
    return value as EegSignalLineType
  }

  return FALLBACK_STYLE.lineType
}

function normalizeGlowIntensity(value: unknown): number {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed)) {
    return 0
  }

  return Math.max(0, Math.min(36, Math.round(parsed)))
}

function buildDefaultStyle(signalKey: string): EegSignalStyle {
  return {
    color: normalizeColorHex(DEFAULT_SIGNAL_COLORS[signalKey] ?? FALLBACK_COLOR, FALLBACK_COLOR),
    lineType: FALLBACK_STYLE.lineType,
    glowIntensity: FALLBACK_STYLE.glowIntensity,
  }
}

function buildKnownDefaultStyles(): Record<string, EegSignalStyle> {
  const styles: Record<string, EegSignalStyle> = {}

  for (const [signalKey, color] of Object.entries(DEFAULT_SIGNAL_COLORS)) {
    styles[signalKey] = {
      color: normalizeColorHex(color, FALLBACK_COLOR),
      lineType: FALLBACK_STYLE.lineType,
      glowIntensity: FALLBACK_STYLE.glowIntensity,
    }
  }

  return styles
}

function readStoredStyles(): Record<string, EegSignalStyle> {
  const defaults = buildKnownDefaultStyles()

  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw === null) {
      return defaults
    }

    const parsed = JSON.parse(raw) as unknown
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return defaults
    }

    const result: Record<string, EegSignalStyle> = { ...defaults }
    for (const [signalKey, value] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        continue
      }

      const typedValue = value as Record<string, unknown>
      const fallbackStyle = defaults[signalKey] ?? buildDefaultStyle(signalKey)
      result[signalKey] = {
        color: normalizeColorHex(typedValue.color, fallbackStyle.color),
        lineType: normalizeLineType(typedValue.lineType),
        glowIntensity: normalizeGlowIntensity(typedValue.glowIntensity),
      }
    }

    return result
  } catch {
    return defaults
  }
}

function writeStoredStyles(stylesByKey: Readonly<Record<string, EegSignalStyle>>): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(stylesByKey))
  } catch {
    // Ignore localStorage failures.
  }
}

export const useEegSignalStyleStore = defineStore('eegSignalStyle', () => {
  const stylesByKey = ref<Record<string, EegSignalStyle>>(readStoredStyles())

  watch(stylesByKey, (styles) => {
    writeStoredStyles(styles)
  }, { deep: true })

  function getSignalStyle(signalKey: string): EegSignalStyle {
    return stylesByKey.value[signalKey] ?? buildDefaultStyle(signalKey)
  }

  function updateSignalStyle(signalKey: string, nextStyle: EegSignalStyle): void {
    stylesByKey.value = {
      ...stylesByKey.value,
      [signalKey]: nextStyle,
    }
  }

  function setSignalColor(signalKey: string, color: string): void {
    const current = getSignalStyle(signalKey)
    updateSignalStyle(signalKey, {
      ...current,
      color: normalizeColorHex(color, current.color),
    })
  }

  function setSignalLineType(signalKey: string, lineType: EegSignalLineType): void {
    const current = getSignalStyle(signalKey)
    updateSignalStyle(signalKey, {
      ...current,
      lineType: normalizeLineType(lineType),
    })
  }

  function setSignalGlowIntensity(signalKey: string, glowIntensity: number): void {
    const current = getSignalStyle(signalKey)
    updateSignalStyle(signalKey, {
      ...current,
      glowIntensity: normalizeGlowIntensity(glowIntensity),
    })
  }

  return {
    stylesByKey,
    getSignalStyle,
    setSignalColor,
    setSignalLineType,
    setSignalGlowIntensity,
  }
})
