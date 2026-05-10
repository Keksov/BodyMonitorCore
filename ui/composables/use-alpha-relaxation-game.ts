import { computed, onBeforeUnmount, ref } from 'vue'
import type { AlphaRelaxationSummary } from '../stores/device'

export type AlphaRelaxationStatus = 'idle' | 'running' | 'finished'
export type AlphaRelaxationPhase = 'inhale' | 'exhale'

export interface UseAlphaRelaxationGameOptions {
  readonly durationMin?: number
}

export interface StartAlphaRelaxationGameOptions {
  readonly durationMin?: number
}

const DEFAULT_DURATION_MIN = 1
const BREATH_CYCLE_MS = 10_000
const MIN_BREATH_SCALE = 0.56
const BREATH_SCALE_SPREAD = 0.44

function normalizeDurationMin(value: number | undefined): number {
  return Number.isInteger(value) && (value ?? 0) > 0 ? value as number : DEFAULT_DURATION_MIN
}

function buildCycleCount(durationSec: number): number {
  return Math.max(1, Math.round(durationSec / (BREATH_CYCLE_MS / 1000)))
}

export function useAlphaRelaxationGame(options: UseAlphaRelaxationGameOptions = {}) {
  const status = ref<AlphaRelaxationStatus>('idle')
  const durationSec = ref(normalizeDurationMin(options.durationMin) * 60)
  const elapsedMs = ref(0)
  const currentSummary = ref<AlphaRelaxationSummary | null>(null)

  let startAtMs = 0
  let frameHandle: number | null = null

  function clearAnimationFrame(): void {
    if (frameHandle !== null) {
      cancelAnimationFrame(frameHandle)
      frameHandle = null
    }
  }

  function finishGame(): void {
    clearAnimationFrame()
    elapsedMs.value = durationSec.value * 1000
    currentSummary.value = {
      version: 1,
      activityId: 'alphaRelaxation',
      recordedAtMs: Date.now(),
      durationSec: durationSec.value,
      cyclesCompleted: buildCycleCount(durationSec.value),
    }
    status.value = 'finished'
  }

  function onAnimationFrame(now: number): void {
    if (status.value !== 'running') {
      return
    }

    const nextElapsedMs = Math.min(durationSec.value * 1000, Math.max(0, now - startAtMs))
    elapsedMs.value = nextElapsedMs

    if (nextElapsedMs >= durationSec.value * 1000) {
      finishGame()
      return
    }

    frameHandle = requestAnimationFrame(onAnimationFrame)
  }

  function startGame(startOptions: StartAlphaRelaxationGameOptions = {}): void {
    clearAnimationFrame()
    durationSec.value = normalizeDurationMin(startOptions.durationMin) * 60
    elapsedMs.value = 0
    currentSummary.value = null
    status.value = 'running'
    startAtMs = performance.now()
    frameHandle = requestAnimationFrame(onAnimationFrame)
  }

  function stopGame(): void {
    clearAnimationFrame()
    elapsedMs.value = 0
    currentSummary.value = null
    status.value = 'idle'
  }

  function resetGame(): void {
    clearAnimationFrame()
    elapsedMs.value = 0
    currentSummary.value = null
    status.value = 'idle'
  }

  const cycleProgress = computed(() => {
    if (status.value === 'finished') {
      return 1
    }

    const normalizedElapsedMs = Math.max(0, elapsedMs.value)
    return (normalizedElapsedMs % BREATH_CYCLE_MS) / BREATH_CYCLE_MS
  })

  const phase = computed<AlphaRelaxationPhase>(() => {
    return cycleProgress.value < 0.5 ? 'inhale' : 'exhale'
  })

  const breathScale = computed(() => {
    const sineValue = (Math.sin((cycleProgress.value * Math.PI * 2) - (Math.PI / 2)) + 1) / 2
    return MIN_BREATH_SCALE + (sineValue * BREATH_SCALE_SPREAD)
  })

  const secondsRemaining = computed(() => {
    if (status.value === 'finished') {
      return 0
    }

    return Math.max(0, Math.ceil((durationSec.value * 1000 - elapsedMs.value) / 1000))
  })

  const completedCycleCount = computed(() => {
    if (status.value === 'finished' && currentSummary.value !== null) {
      return currentSummary.value.cyclesCompleted
    }

    return Math.floor(elapsedMs.value / BREATH_CYCLE_MS)
  })

  onBeforeUnmount(() => {
    clearAnimationFrame()
  })

  return {
    status,
    phase,
    breathScale,
    secondsRemaining,
    completedCycleCount,
    currentSummary,
    startGame,
    stopGame,
    resetGame,
  }
}