import { computed, onBeforeUnmount, ref } from 'vue'
import type { AttentionCalibrationSummary } from '../stores/device'

export type AttentionCalibrationShape = 'circle' | 'triangle'
export type AttentionCalibrationOperationPreset = 'add-only' | 'add-subtract' | 'add-subtract-multiply' | 'all'
export type AttentionCalibrationNumberScalePreset = 'small' | 'small-large'
export type AttentionCalibrationMovingSpeed = 'slow' | 'medium' | 'fast'

export interface AttentionCalibrationToken {
  readonly id: number
  readonly number: number
  readonly shape: AttentionCalibrationShape
  readonly expression: string
}

export interface UseAttentionCalibrationGameOptions {
  readonly durationSec?: number
  readonly boardSize?: number
  readonly firstShape?: AttentionCalibrationShape
  readonly operationPreset?: AttentionCalibrationOperationPreset
  readonly numberScalePreset?: AttentionCalibrationNumberScalePreset
}

export interface StartAttentionCalibrationGameOptions {
  readonly operationPreset?: AttentionCalibrationOperationPreset
  readonly numberScalePreset?: AttentionCalibrationNumberScalePreset
  readonly durationMin?: number
  readonly movingShapesPct?: number
  readonly movingSpeed?: AttentionCalibrationMovingSpeed
}

type AttentionCalibrationStatus = 'idle' | 'running' | 'finished'
type TokenFlashState = 'wrong'
type ArithmeticOperation = 'add' | 'subtract' | 'multiply' | 'divide'

const DEFAULT_DURATION_SEC = 120
const DEFAULT_BOARD_SIZE = 8
const DEFAULT_FIRST_SHAPE: AttentionCalibrationShape = 'circle'
const DEFAULT_OPERATION_PRESET: AttentionCalibrationOperationPreset = 'add-only'
const DEFAULT_NUMBER_SCALE_PRESET: AttentionCalibrationNumberScalePreset = 'small'
const DUPLICATE_PROBABILITY = 0.45
const MAX_EXPRESSION_ATTEMPTS = 12
const WRONG_FLASH_MS = 320

const SMALL_OPERAND_LIMIT = 9
const LARGE_OPERAND_LIMIT = 20

function alternateShape(shape: AttentionCalibrationShape): AttentionCalibrationShape {
  return shape === 'circle' ? 'triangle' : 'circle'
}

function shapeForNumber(number: number, firstShape: AttentionCalibrationShape): AttentionCalibrationShape {
  return number % 2 === 1 ? firstShape : alternateShape(firstShape)
}

function pickRandomValue<T>(values: readonly T[]): T {
  return values[Math.floor(Math.random() * values.length)]
}

function randomInt(minValue: number, maxValue: number): number {
  return minValue + Math.floor(Math.random() * ((maxValue - minValue) + 1))
}

function getOperationPool(preset: AttentionCalibrationOperationPreset): readonly ArithmeticOperation[] {
  switch (preset) {
    case 'add-only':
      return ['add']
    case 'add-subtract':
      return ['add', 'subtract']
    case 'add-subtract-multiply':
      return ['add', 'subtract', 'multiply']
    case 'all':
      return ['add', 'subtract', 'multiply', 'divide']
  }
}

function getPreferredOperandLimit(preset: AttentionCalibrationNumberScalePreset): number {
  return preset === 'small' ? SMALL_OPERAND_LIMIT : LARGE_OPERAND_LIMIT
}

function createAdditionExpression(number: number, operandLimit: number, strict: boolean): string | null {
  if (number <= 1) {
    return null
  }

  const minLeftValue = strict ? Math.max(1, number - operandLimit) : 1
  const maxLeftValue = strict ? Math.min(operandLimit, number - 1) : number - 1
  if (minLeftValue > maxLeftValue) {
    return null
  }

  const leftValue = randomInt(minLeftValue, maxLeftValue)
  return `${leftValue}+${number - leftValue}`
}

function createSubtractionExpression(number: number, operandLimit: number, strict: boolean): string | null {
  const maxOffset = strict ? Math.min(operandLimit - number, operandLimit - 1) : Math.max(2, Math.min(operandLimit, number + 4))
  if (maxOffset < 1) {
    return null
  }

  const offset = randomInt(1, maxOffset)
  return `${number + offset}-${offset}`
}

function createMultiplicationExpression(number: number, operandLimit: number, strict: boolean): string | null {
  const factorCandidates: number[] = []
  for (let factor = 2; factor <= Math.min(9, number); factor += 1) {
    if (number % factor === 0 && (!strict || number / factor <= operandLimit)) {
      factorCandidates.push(factor)
    }
  }

  if (factorCandidates.length > 0) {
    const leftValue = pickRandomValue(factorCandidates)
    return `${leftValue}*${number / leftValue}`
  }

  return strict ? null : `${number}*1`
}

function createDivisionExpression(number: number, operandLimit: number, strict: boolean): string | null {
  const divisors: number[] = []
  for (let divisor = 2; divisor <= operandLimit; divisor += 1) {
    if (!strict || (number * divisor) <= operandLimit) {
      divisors.push(divisor)
    }
  }

  if (divisors.length === 0) {
    return null
  }

  const divisor = pickRandomValue(divisors)
  return `${number * divisor}/${divisor}`
}

function createExpressionByOperation(
  number: number,
  operation: ArithmeticOperation,
  operandLimit: number,
  strict: boolean
): string | null {
  switch (operation) {
    case 'add':
      return createAdditionExpression(number, operandLimit, strict)
    case 'subtract':
      return createSubtractionExpression(number, operandLimit, strict)
    case 'multiply':
      return createMultiplicationExpression(number, operandLimit, strict)
    case 'divide':
      return createDivisionExpression(number, operandLimit, strict)
  }
}

function buildArithmeticExpression(
  number: number,
  operationPreset: AttentionCalibrationOperationPreset,
  numberScalePreset: AttentionCalibrationNumberScalePreset,
  excludedExpressions: readonly string[] = []
): string {
  const blockedExpressions = new Set(excludedExpressions)
  let fallbackExpression: string | null = null
  const operationPool = getOperationPool(operationPreset)
  const operandLimit = getPreferredOperandLimit(numberScalePreset)

  for (const strict of [true, false]) {
    for (let attempt = 0; attempt < MAX_EXPRESSION_ATTEMPTS; attempt += 1) {
      const operation = pickRandomValue(operationPool)
      const expression = createExpressionByOperation(number, operation, operandLimit, strict)
      if (expression === null) {
        continue
      }

      fallbackExpression ??= expression
      if (!blockedExpressions.has(expression)) {
        return expression
      }
    }
  }

  return fallbackExpression ?? `${number}+0`
}

function buildToken(
  tokenId: number,
  number: number,
  shape: AttentionCalibrationShape,
  operationPreset: AttentionCalibrationOperationPreset,
  numberScalePreset: AttentionCalibrationNumberScalePreset,
  excludedExpressions: readonly string[] = []
): AttentionCalibrationToken {
  return {
    id: tokenId,
    number,
    shape,
    expression: buildArithmeticExpression(number, operationPreset, numberScalePreset, excludedExpressions),
  }
}

function buildTokensForNumber(
  number: number,
  firstShape: AttentionCalibrationShape,
  nextTokenId: () => number,
  operationPreset: AttentionCalibrationOperationPreset,
  numberScalePreset: AttentionCalibrationNumberScalePreset,
  duplicateNumber: boolean
): AttentionCalibrationToken[] {
  const usedExpressions: string[] = []
  const correctShape = shapeForNumber(number, firstShape)
  const correctToken = buildToken(nextTokenId(), number, correctShape, operationPreset, numberScalePreset, usedExpressions)
  usedExpressions.push(correctToken.expression)

  if (!duplicateNumber) {
    return [correctToken]
  }

  const duplicateToken = buildToken(nextTokenId(), number, alternateShape(correctShape), operationPreset, numberScalePreset, usedExpressions)
  return [correctToken, duplicateToken]
}

function countDistinctNumbers(tokens: readonly AttentionCalibrationToken[]): number {
  return new Set(tokens.map((token) => token.number)).size
}

function hasTokenForShape(
  tokens: readonly AttentionCalibrationToken[],
  number: number,
  shape: AttentionCalibrationShape
): boolean {
  return tokens.some((token) => token.number === number && token.shape === shape)
}

function ensureNumberTokens(
  tokens: readonly AttentionCalibrationToken[],
  number: number,
  firstShape: AttentionCalibrationShape,
  nextTokenId: () => number,
  operationPreset: AttentionCalibrationOperationPreset,
  numberScalePreset: AttentionCalibrationNumberScalePreset,
  duplicateNumber: boolean
): AttentionCalibrationToken[] {
  const nextTokens = [...tokens]
  const correctShape = shapeForNumber(number, firstShape)
  const usedExpressions = nextTokens
    .filter((token) => token.number === number)
    .map((token) => token.expression)

  if (!hasTokenForShape(nextTokens, number, correctShape)) {
    const correctToken = buildToken(nextTokenId(), number, correctShape, operationPreset, numberScalePreset, usedExpressions)
    nextTokens.push(correctToken)
    usedExpressions.push(correctToken.expression)
  }

  if (!duplicateNumber) {
    return nextTokens
  }

  const duplicateShape = alternateShape(correctShape)
  if (!hasTokenForShape(nextTokens, number, duplicateShape)) {
    nextTokens.push(buildToken(nextTokenId(), number, duplicateShape, operationPreset, numberScalePreset, usedExpressions))
  }

  return nextTokens
}

function shouldDuplicateNumber(number: number, startNumber: number): boolean {
  if (number === startNumber) {
    return true
  }

  return Math.random() < DUPLICATE_PROBABILITY
}

function shuffleTokens(tokens: readonly AttentionCalibrationToken[]): AttentionCalibrationToken[] {
  const nextTokens = [...tokens]

  for (let index = nextTokens.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1))
    const currentToken = nextTokens[index]
    nextTokens[index] = nextTokens[swapIndex]
    nextTokens[swapIndex] = currentToken
  }

  return nextTokens
}

export function useAttentionCalibrationGame(options: UseAttentionCalibrationGameOptions = {}) {
  const initialDurationSec = Math.max(1, Math.trunc(options.durationSec ?? DEFAULT_DURATION_SEC))
  const durationSec = ref(initialDurationSec)
  const boardSize = Math.max(4, Math.trunc(options.boardSize ?? DEFAULT_BOARD_SIZE))
  const firstShape = options.firstShape ?? DEFAULT_FIRST_SHAPE
  const currentOperationPreset = ref(options.operationPreset ?? DEFAULT_OPERATION_PRESET)
  const currentNumberScalePreset = ref(options.numberScalePreset ?? DEFAULT_NUMBER_SCALE_PRESET)
  const currentMovingShapesPct = ref(0)
  const currentMovingSpeed = ref<AttentionCalibrationMovingSpeed>('medium')

  const status = ref<AttentionCalibrationStatus>('idle')
  const secondsRemaining = ref(initialDurationSec)
  const expectedNumber = ref(1)
  const visibleTokens = ref<AttentionCalibrationToken[]>([])
  const errorCount = ref(0)
  const finishedSummary = ref<AttentionCalibrationSummary | null>(null)
  const flashStates = ref<Record<number, TokenFlashState>>({})

  const completedTargetCount = computed(() => Math.max(0, expectedNumber.value - 1))
  const requiredShape = computed<AttentionCalibrationShape>(() => shapeForNumber(expectedNumber.value, firstShape))

  let countdownTimer: ReturnType<typeof setInterval> | null = null
  let nextTokenId = 1
  const flashTimeoutHandles = new Map<number, ReturnType<typeof setTimeout>>()

  function takeNextTokenId(): number {
    const tokenId = nextTokenId
    nextTokenId += 1
    return tokenId
  }

  function clearCountdownTimer(): void {
    if (countdownTimer !== null) {
      clearInterval(countdownTimer)
      countdownTimer = null
    }
  }

  function clearTokenFlash(tokenId: number): void {
    const nextFlashStates = { ...flashStates.value }
    if (!(tokenId in nextFlashStates)) {
      return
    }

    delete nextFlashStates[tokenId]
    flashStates.value = nextFlashStates

    const timeoutHandle = flashTimeoutHandles.get(tokenId)
    if (timeoutHandle !== undefined) {
      clearTimeout(timeoutHandle)
      flashTimeoutHandles.delete(tokenId)
    }
  }

  function clearAllFlashes(): void {
    for (const timeoutHandle of flashTimeoutHandles.values()) {
      clearTimeout(timeoutHandle)
    }

    flashTimeoutHandles.clear()
    flashStates.value = {}
  }

  function buildVisibleTokens(startNumber: number): AttentionCalibrationToken[] {
    const tokens: AttentionCalibrationToken[] = []

    for (let index = 0; index < boardSize; index += 1) {
      tokens.push(...buildTokensForNumber(
        startNumber + index,
        firstShape,
        takeNextTokenId,
        currentOperationPreset.value,
        currentNumberScalePreset.value,
        shouldDuplicateNumber(startNumber + index, startNumber)
      ))
    }

    return shuffleTokens(tokens)
  }

  function finishGame(): void {
    if (status.value !== 'running') {
      return
    }

    clearCountdownTimer()
    status.value = 'finished'
    finishedSummary.value = {
      version: 1,
      activityId: 'attention',
      recordedAtMs: Date.now(),
      durationSec: durationSec.value,
      completedTargetCount: completedTargetCount.value,
      errorCount: errorCount.value,
    }
  }

  function resetGame(): void {
    clearCountdownTimer()
    clearAllFlashes()
    status.value = 'idle'
    secondsRemaining.value = durationSec.value
    expectedNumber.value = 1
    visibleTokens.value = []
    errorCount.value = 0
    finishedSummary.value = null
    nextTokenId = 1
  }

  function startGame(startOptions: StartAttentionCalibrationGameOptions = {}): void {
    currentOperationPreset.value = startOptions.operationPreset ?? currentOperationPreset.value
    currentNumberScalePreset.value = startOptions.numberScalePreset ?? currentNumberScalePreset.value
    if (startOptions.durationMin !== undefined) {
      durationSec.value = Math.max(1, Math.trunc(startOptions.durationMin)) * 60
    }

    if (startOptions.movingShapesPct !== undefined) {
      currentMovingShapesPct.value = Math.max(0, Math.min(100, Math.trunc(startOptions.movingShapesPct)))
    }

    if (startOptions.movingSpeed !== undefined) {
      currentMovingSpeed.value = startOptions.movingSpeed
    }

    resetGame()
    status.value = 'running'
    visibleTokens.value = buildVisibleTokens(1)

    countdownTimer = setInterval(() => {
      if (secondsRemaining.value <= 1) {
        secondsRemaining.value = 0
        finishGame()
        return
      }

      secondsRemaining.value -= 1
    }, 1000)
  }

  function markWrongToken(tokenId: number): void {
    const existingTimeout = flashTimeoutHandles.get(tokenId)
    if (existingTimeout !== undefined) {
      clearTimeout(existingTimeout)
    }

    flashStates.value = {
      ...flashStates.value,
      [tokenId]: 'wrong',
    }

    flashTimeoutHandles.set(tokenId, setTimeout(() => {
      clearTokenFlash(tokenId)
    }, WRONG_FLASH_MS))
  }

  function handleTokenClick(token: AttentionCalibrationToken): boolean {
    if (status.value !== 'running') {
      return false
    }

    if (token.number !== expectedNumber.value || token.shape !== requiredShape.value) {
      errorCount.value += 1
      markWrongToken(token.id)
      return false
    }

    clearTokenFlash(token.id)
    expectedNumber.value += 1

    let remainingTokens = visibleTokens.value.filter((entry) => entry.number !== token.number)
    remainingTokens = ensureNumberTokens(
      remainingTokens,
      expectedNumber.value,
      firstShape,
      takeNextTokenId,
      currentOperationPreset.value,
      currentNumberScalePreset.value,
      true
    )

    let nextVisibleNumber = remainingTokens.reduce((maxNumber, entry) => {
      return Math.max(maxNumber, entry.number)
    }, expectedNumber.value - 1) + 1

    while (countDistinctNumbers(remainingTokens) < boardSize) {
      remainingTokens = [
        ...remainingTokens,
        ...buildTokensForNumber(
          nextVisibleNumber,
          firstShape,
          takeNextTokenId,
          currentOperationPreset.value,
          currentNumberScalePreset.value,
          shouldDuplicateNumber(nextVisibleNumber, expectedNumber.value)
        ),
      ]
      nextVisibleNumber += 1
    }

    visibleTokens.value = shuffleTokens(remainingTokens)
    return true
  }

  function getTokenFlashState(tokenId: number): TokenFlashState | null {
    return flashStates.value[tokenId] ?? null
  }

  onBeforeUnmount(() => {
    resetGame()
  })

  return {
    durationSec,
    boardSize,
    status,
    secondsRemaining,
    expectedNumber,
    visibleTokens,
    errorCount,
    completedTargetCount,
    requiredShape,
    currentOperationPreset,
    currentNumberScalePreset,
    currentMovingShapesPct,
    currentMovingSpeed,
    finishedSummary,
    startGame,
    resetGame,
    handleTokenClick,
    getTokenFlashState,
  }
}