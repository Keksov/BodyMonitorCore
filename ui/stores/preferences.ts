import { defineStore } from 'pinia'
import { ref, watch } from 'vue'

export type EegDisplayMode = 'radar' | 'bands' | 'line'
export type EegDataCorrection = 'raw' | 'calibrated'
export type EegDataSource = 'bands' | 'algo-bp'

const EEG_MODE_KEY = 'eegDisplayMode'
const EEG_BAND_WINDOW_SEC_KEY = 'eegBandWindowSec'
const EEG_DATA_CORRECTION_KEY = 'eegDataCorrection'
const EEG_DATA_SOURCE_KEY = 'eegDataSource'
const EEG_MODE_DEFAULT: EegDisplayMode = 'bands'
const EEG_BAND_WINDOW_SEC_DEFAULT = 10
const EEG_DATA_CORRECTION_DEFAULT: EegDataCorrection = 'raw'
const EEG_DATA_SOURCE_DEFAULT: EegDataSource = 'bands'
const VALID_EEG_MODES: readonly EegDisplayMode[] = ['bands', 'radar', 'line']
const VALID_EEG_DATA_CORRECTIONS: readonly EegDataCorrection[] = ['raw', 'calibrated']
const VALID_EEG_DATA_SOURCES: readonly EegDataSource[] = ['bands', 'algo-bp']

function sanitizeEegBandWindowSec(value: unknown): number {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 0) {
    return EEG_BAND_WINDOW_SEC_DEFAULT
  }

  if (parsed === 0) {
    return 0
  }

  return Math.max(1, Math.trunc(parsed))
}

function readStoredEegMode(): EegDisplayMode {
  const stored = localStorage.getItem(EEG_MODE_KEY)
  if (stored !== null && (VALID_EEG_MODES as readonly string[]).includes(stored)) {
    return stored as EegDisplayMode
  }

  return EEG_MODE_DEFAULT
}

function readStoredEegBandWindowSec(): number {
  return sanitizeEegBandWindowSec(localStorage.getItem(EEG_BAND_WINDOW_SEC_KEY))
}

function readStoredEegDataCorrection(): EegDataCorrection {
  const stored = localStorage.getItem(EEG_DATA_CORRECTION_KEY)
  if (stored === 'absolute') {
    return 'raw'
  }

  if (stored !== null && (VALID_EEG_DATA_CORRECTIONS as readonly string[]).includes(stored)) {
    return stored as EegDataCorrection
  }

  return EEG_DATA_CORRECTION_DEFAULT
}

function readStoredEegDataSource(): EegDataSource {
  const stored = localStorage.getItem(EEG_DATA_SOURCE_KEY)
  if (stored !== null && (VALID_EEG_DATA_SOURCES as readonly string[]).includes(stored)) {
    return stored as EegDataSource
  }

  return EEG_DATA_SOURCE_DEFAULT
}

export const usePreferencesStore = defineStore('preferences', () => {
  const eegDisplayMode = ref<EegDisplayMode>(readStoredEegMode())
  const eegBandWindowSec = ref<number>(readStoredEegBandWindowSec())
  const eegDataCorrection = ref<EegDataCorrection>(readStoredEegDataCorrection())
  const eegDataSource = ref<EegDataSource>(readStoredEegDataSource())

  watch(eegDisplayMode, (mode) => {
    localStorage.setItem(EEG_MODE_KEY, mode)
  })

  watch(eegBandWindowSec, (windowSec) => {
    const normalizedWindowSec = sanitizeEegBandWindowSec(windowSec)
    if (normalizedWindowSec !== windowSec) {
      eegBandWindowSec.value = normalizedWindowSec
      return
    }

    localStorage.setItem(EEG_BAND_WINDOW_SEC_KEY, String(normalizedWindowSec))
  }, { immediate: true })

  watch(eegDataCorrection, (mode) => {
    localStorage.setItem(EEG_DATA_CORRECTION_KEY, mode)
  })

  watch(eegDataSource, (source) => {
    localStorage.setItem(EEG_DATA_SOURCE_KEY, source)
  })

  return {
    eegDisplayMode,
    eegBandWindowSec,
    eegDataCorrection,
    eegDataSource,
  }
})
