import { defineStore } from 'pinia'
import { ref, watch } from 'vue'

export type EegDisplayMode = 'radar' | 'bands'
export type EegBandScaleMode = 'raw' | 'normalized' | 'calibrated'

const EEG_MODE_KEY = 'eegDisplayMode'
const EEG_BAND_WINDOW_SEC_KEY = 'eegBandWindowSec'
const EEG_BAND_SCALE_MODE_KEY = 'eegBandScaleMode'
const EEG_MODE_DEFAULT: EegDisplayMode = 'bands'
const EEG_BAND_WINDOW_SEC_DEFAULT = 10
const EEG_BAND_SCALE_MODE_DEFAULT: EegBandScaleMode = 'raw'
const VALID_EEG_MODES: readonly EegDisplayMode[] = ['bands', 'radar']
const VALID_EEG_BAND_SCALE_MODES: readonly EegBandScaleMode[] = ['raw', 'normalized', 'calibrated']

function sanitizeEegBandWindowSec(value: unknown): number {
  const parsed = typeof value === 'number'
    ? value
    : typeof value === 'string'
      ? Number(value)
      : Number.NaN

  if (!Number.isFinite(parsed) || parsed < 1) {
    return EEG_BAND_WINDOW_SEC_DEFAULT
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

function readStoredEegBandScaleMode(): EegBandScaleMode {
  const stored = localStorage.getItem(EEG_BAND_SCALE_MODE_KEY)
  if (stored === 'absolute') {
    return 'raw'
  }

  if (stored !== null && (VALID_EEG_BAND_SCALE_MODES as readonly string[]).includes(stored)) {
    return stored as EegBandScaleMode
  }

  return EEG_BAND_SCALE_MODE_DEFAULT
}

export const usePreferencesStore = defineStore('preferences', () => {
  const eegDisplayMode = ref<EegDisplayMode>(readStoredEegMode())
  const eegBandWindowSec = ref<number>(readStoredEegBandWindowSec())
  const eegBandScaleMode = ref<EegBandScaleMode>(readStoredEegBandScaleMode())

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

  watch(eegBandScaleMode, (mode) => {
    localStorage.setItem(EEG_BAND_SCALE_MODE_KEY, mode)
  })

  return {
    eegDisplayMode,
    eegBandWindowSec,
    eegBandScaleMode,
  }
})
