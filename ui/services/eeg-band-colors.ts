import type { LogChartSeriesKey } from '@protocol'

import type { EegBandKey } from './eeg-band-snapshot'

export const EEG_BAND_COLORS: Record<EegBandKey, string> = {
  delta: '#F77F00',
  theta: '#E4572E',
  alpha1: '#F4D35E',
  alpha2: '#EEC643',
  beta1: '#66BB6A',
  beta2: '#2E7D32',
  gamma1: '#3A86FF',
  gamma2: '#7B2CBF',
}

export const COMBINED_EEG_BAND_COLORS = {
  delta: '#F77F00',
  theta: '#E4572E',
  alpha: '#EEC643',
  beta: '#2E7D32',
  gamma: '#5E60CE',
} as const

export type CombinedEegBandKey = keyof typeof COMBINED_EEG_BAND_COLORS

export const EEG_FAMILY_BASE_COLORS: Record<CombinedEegBandKey, string> = {
  delta: EEG_BAND_COLORS.delta,
  theta: EEG_BAND_COLORS.theta,
  alpha: EEG_BAND_COLORS.alpha2,
  beta: EEG_BAND_COLORS.beta2,
  gamma: COMBINED_EEG_BAND_COLORS.gamma,
}

export const isEegBandSeriesKey = (key: LogChartSeriesKey): key is EegBandKey => {
  return key in EEG_BAND_COLORS
}
