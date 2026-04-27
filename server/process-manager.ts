import { randomUUID } from "node:crypto"
import { existsSync } from "node:fs"
import { basename, dirname, resolve } from "node:path"
import type { PipedSubprocess } from "bun"
import {
  isServerReadyLine,
  parseDeviceInfoFromJson,
  parseJsonLine,
  parseStdioAck,
  isStdioReadyLine,
  type DeviceInfo,
  type BodyMonitorOutputEvent,
  type BodyMonitorState,
  type BodyMonitorStdioAckEvent
} from "./protocol"

type ChildProcess = PipedSubprocess

export interface ProcessStateSnapshot {
  readonly state: BodyMonitorState
  readonly sessionState: BodyMonitorState
  readonly runId?: string
  readonly commandLine?: string
}

export interface StartResult {
  readonly runId: string
}

export interface ProcessManagerCallbacks {
  readonly onStateChange?: (aSnapshot: ProcessStateSnapshot) => void
  readonly onStarted?: (aRunId: string, aParams: readonly string[], aCommandLine: string) => void
  readonly onScanCommand?: (aRunId: string, aCommandLine: string) => void
  readonly onLine?: (aEvent: BodyMonitorOutputEvent) => void
  readonly onDevice?: (aRunId: string, aDevice: DeviceInfo) => void
  readonly onDevices?: (aRunId: string, aDevices: readonly DeviceInfo[]) => void
  readonly onError?: (aMessage: string, aRunId?: string) => void
  readonly onExit?: (aRunId: string, aExitCode: number) => void
  readonly onStdioAck?: (aAck: BodyMonitorStdioAckEvent) => void
  readonly onStdioReady?: () => void
}

const STOP_TIMEOUT_MS = 5000
const DEFAULT_SERVER_KEEP_ALIVE_SEC = 15
const STOP_ACTIVE_WORKERS_ERROR = "Stop active workers first"

type StdioSessionState = "idle" | "starting" | "running" | "stopping"

const waitFor = async (aPromise: Promise<number>, aTimeoutMs: number): Promise<boolean> => {
  let timer: ReturnType<typeof setTimeout>
  const completed = await Promise.race([
    aPromise.then(() => true),
    new Promise<boolean>((resolvePromise) => {
      timer = setTimeout(() => resolvePromise(false), aTimeoutMs)
    })
  ])

  clearTimeout(timer!)
  return completed
}

const quoteCommandLineArg = (aValue: string): string => {
  if (aValue === "") {
    return '""'
  }

  if (!/[\s"]/u.test(aValue)) {
    return aValue
  }

  let result = '"'
  let backslashCount = 0

  for (const char of aValue) {
    if (char === "\\") {
      backslashCount++
      continue
    }

    if (char === '"') {
      result += "\\".repeat(backslashCount * 2 + 1) + char
      backslashCount = 0
      continue
    }

    result += "\\".repeat(backslashCount) + char
    backslashCount = 0
  }

  result += "\\".repeat(backslashCount * 2) + '"'
  return result
}

const buildCommandLine = (aExecutablePath: string, aParams: readonly string[]): string => {
  return [basename(aExecutablePath), ...aParams].map(quoteCommandLineArg).join(" ")
}

const resolveBodyMonitorExecutablePath = (aWorkspaceRoot: string): {
  readonly bodyMonitorCwd: string
  readonly bodyMonitorExePath: string
} => {
  const candidatePaths = [
    resolve(import.meta.dir, "..", "cli", "build", "x64", "BodyMonitor.exe"),
    resolve(aWorkspaceRoot, "BodyMonitorCore", "cli", "build", "x64", "BodyMonitor.exe"),
    resolve(aWorkspaceRoot, "products", "BodyMonitorCore", "cli", "BodyMonitor", "build", "x64", "BodyMonitor.exe"),
  ]

  const bodyMonitorExePath = candidatePaths.find((candidatePath) => existsSync(candidatePath)) ?? candidatePaths[0]

  return {
    bodyMonitorCwd: dirname(bodyMonitorExePath),
    bodyMonitorExePath,
  }
}

const forEachLine = async (
  aStream: ReadableStream<Uint8Array<ArrayBuffer>> | null,
  aLineHandler: (aLine: string) => void | Promise<void>
): Promise<void> => {
  if (aStream === null) {
    return
  }

  const decoder = new TextDecoder()
  let tail = ""

  for await (const chunk of aStream) {
    tail += decoder.decode(chunk, { stream: true })

    while (true) {
      const endIndex = tail.indexOf("\n")
      if (endIndex < 0) {
        break
      }

      const line = tail.slice(0, endIndex).replace(/\r$/, "")
      tail = tail.slice(endIndex + 1)
      if (line !== "") {
        await aLineHandler(line)
      }
    }
  }

  tail += decoder.decode()
  const finalLine = tail.replace(/\r$/, "")
  if (finalLine !== "") {
    await aLineHandler(finalLine)
  }
}

export class ProcessManager {
  public readonly kind = "bodymonitor" as const
  private readonly bodyMonitorExePath: string
  private readonly bodyMonitorCwd: string
  private keepAliveTimer: ReturnType<typeof setInterval> | null = null
  private childProcess: ChildProcess | null = null
  private callbacks: ProcessManagerCallbacks | null = null
  private state: BodyMonitorState = "idle"
  private activeRunId: string | null = null
  private activeParams: readonly string[] = []
  private accumulatedDevices: DeviceInfo[] = []
  private stdioState: StdioSessionState = "idle"
  private pendingListDevicesAfterStop = false
  private pendingListDevicesAfterRestart = false
  private serverKeepAliveSec = DEFAULT_SERVER_KEEP_ALIVE_SEC
  private serverInitBle = true

  public constructor(aWorkspaceRoot: string) {
    const { bodyMonitorCwd, bodyMonitorExePath } = resolveBodyMonitorExecutablePath(aWorkspaceRoot)
    this.bodyMonitorCwd = bodyMonitorCwd
    this.bodyMonitorExePath = bodyMonitorExePath
  }

  public getState(): ProcessStateSnapshot {
    if (this.activeRunId === null) {
      return {
        state: this.state,
        sessionState: "idle",
      }
    }

    return {
      state: this.state,
      sessionState: this.stdioState,
      runId: this.activeRunId,
      commandLine: buildCommandLine(this.bodyMonitorExePath, this.activeParams)
    }
  }

  public async stop(): Promise<boolean> {
    if (this.childProcess === null || this.activeRunId === null) {
      return false
    }

    this.pendingListDevicesAfterStop = false
    this.pendingListDevicesAfterRestart = false

    const child = this.childProcess
    const runId = this.activeRunId

    this.setState("stopping")
    child.kill()

    const stopped = await waitFor(child.exited, STOP_TIMEOUT_MS)
    if (!stopped) {
      child.kill(9)
      await child.exited
    }

    if (this.activeRunId === runId) {
      this.resetActiveProcess(runId)
      this.setState("idle")
    }

    return true
  }

  public async startServer(
    aCallbacks: ProcessManagerCallbacks,
    aKeepAliveSec = DEFAULT_SERVER_KEEP_ALIVE_SEC,
    aInitBle = true
  ): Promise<StartResult> {
    const params = [
      "--server",
      `--keep-alive-sec=${aKeepAliveSec}`,
      "--log",
      "-",
      "--log-format=jsonl",
      ...(aInitBle ? ["--init-ble"] : []),
    ]

    if (this.childProcess !== null || this.state !== "idle") {
      throw new Error("BodyMonitor process is already active")
    }

    const runId = randomUUID()

    this.callbacks = aCallbacks
    this.accumulatedDevices = []
    this.activeRunId = runId
    this.activeParams = [...params]
    this.serverKeepAliveSec = aKeepAliveSec
    this.serverInitBle = aInitBle
    this.setState("starting")

    let child: ChildProcess
    try {
      child = Bun.spawn([this.bodyMonitorExePath, ...params], {
        cwd: this.bodyMonitorCwd,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe"
      })
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to spawn BodyMonitor.exe"
      this.callbacks?.onError?.(message, runId)
      this.resetActiveProcess(runId)
      this.setState("idle")
      throw error
    }

    this.childProcess = child
    this.callbacks?.onStarted?.(
      runId,
      this.activeParams,
      buildCommandLine(this.bodyMonitorExePath, this.activeParams)
    )
    this.setState("running")

    void this.forwardStream(runId, child.stdout, "stdout")
    void this.forwardStream(runId, child.stderr, "stderr")
    void this.watchExit(runId, child)

    this.keepAliveTimer = setInterval(() => {
      this.sendServerPing()
    }, aKeepAliveSec * 1000)
    return { runId }
  }

  private sendStdinCommand(aCommand: Record<string, unknown>): void {
    const child = this.childProcess
    if (child === null) {
      return
    }

    if (child.exitCode !== null) {
      return
    }

    const line = JSON.stringify(aCommand) + "\n"
    console.log(`[exe:stdin] ${line.trimEnd()}`)

    try {
      const writeResult = child.stdin.write(new TextEncoder().encode(line))
      void Promise.resolve(writeResult).catch((error) => {
        const message = error instanceof Error
          ? `Failed to write command to BodyMonitor stdin: ${error.message}`
          : "Failed to write command to BodyMonitor stdin"
        this.callbacks?.onError?.(message, this.activeRunId ?? undefined)
      })
    } catch (error) {
      const message = error instanceof Error
        ? `Failed to write command to BodyMonitor stdin: ${error.message}`
        : "Failed to write command to BodyMonitor stdin"
      this.callbacks?.onError?.(message, this.activeRunId ?? undefined)
    }
  }

  public sendStdioConfigure(aParams: readonly string[]): void {
    this.sendStdinCommand({ cmd: "configure", params: aParams })
  }

  public sendStdioStart(): void {
    this.stdioState = "starting"
    this.sendStdinCommand({ cmd: "start" })
  }

  public sendStdioStop(): void {
    this.stdioState = "stopping"
    this.sendStdinCommand({ cmd: "stop" })
  }

  public sendStdioSetParam(aKey: string, aValue: string): void {
    this.sendStdinCommand({ cmd: "set_param", key: aKey, value: aValue })
  }

  public sendStdioQuit(): void {
    this.pendingListDevicesAfterStop = false
    this.pendingListDevicesAfterRestart = false
    this.sendStdinCommand({ cmd: "quit" })
  }

  public sendServerListDevices(): void {
    if (this.stdioState !== "idle") {
      this.queueListDevicesAfterRestart()
      return
    }

    this.dispatchServerListDevices()
  }

  private queueListDevicesAfterRestart(): void {
    this.pendingListDevicesAfterStop = false
    if (this.pendingListDevicesAfterRestart) {
      return
    }

    this.pendingListDevicesAfterRestart = true
    this.stdioState = "stopping"
    this.sendStdinCommand({ cmd: "quit" })
  }

  private dispatchServerListDevices(): void {
    this.accumulatedDevices = []
    if (this.activeRunId !== null) {
      this.callbacks?.onScanCommand?.(
        this.activeRunId,
        buildCommandLine(this.bodyMonitorExePath, this.activeParams)
      )
    }
    this.sendStdinCommand({ cmd: "list_devices" })
  }

  private sendServerPing(): void {
    this.sendStdinCommand({ cmd: "ping" })
  }

  private handleServerReady(): void {
    this.callbacks?.onStdioReady?.()

    if (!this.pendingListDevicesAfterRestart) {
      return
    }

    this.pendingListDevicesAfterRestart = false
    this.dispatchServerListDevices()
  }

  private async restartServerForPendingListDevices(aCallbacks: ProcessManagerCallbacks): Promise<void> {
    try {
      await this.startServer(aCallbacks, this.serverKeepAliveSec, this.serverInitBle)
    } catch (error) {
      this.pendingListDevicesAfterRestart = false

      const message = error instanceof Error
        ? `Failed to restart BodyMonitor for list_devices: ${error.message}`
        : "Failed to restart BodyMonitor for list_devices"
      aCallbacks.onError?.(message)
    }
  }

  private setState(aState: BodyMonitorState): void {
    this.state = aState
    this.callbacks?.onStateChange?.(this.getState())
  }

  private async forwardStream(
    aRunId: string,
    aStream: ReadableStream<Uint8Array<ArrayBuffer>> | null,
    aStreamName: "stdout" | "stderr"
  ): Promise<void> {
    await forEachLine(aStream, async (line) => {
      if (this.activeRunId !== aRunId) {
        return
      }

      console.log(`[exe:${aStreamName}] ${line}`)

      const parsedJson = parseJsonLine(line) ?? undefined

      if (aStreamName === "stdout" && parsedJson !== undefined) {
        const ack = parseStdioAck(parsedJson)
        if (ack !== null) {
          if (ack.cmd === "start") {
            this.stdioState = ack.ok ? "running" : "idle"
          }

          if (ack.cmd === "stop") {
            this.stdioState = ack.ok ? "idle" : "running"
          }

          if (ack.cmd === "quit") {
            this.pendingListDevicesAfterStop = false
            this.stdioState = "idle"
          }

          if (ack.cmd === "list_devices" && ack.ok) {
            this.callbacks?.onDevices?.(aRunId, [...this.accumulatedDevices])
          }

          if (ack.cmd === "list_devices" && !ack.ok && ack.error === STOP_ACTIVE_WORKERS_ERROR) {
            // The backend still has active workers although our local state drifted.
            this.queueListDevicesAfterRestart()
            return
          }

          const shouldDispatchPendingListDevices = ack.cmd === "stop" && ack.ok && this.pendingListDevicesAfterStop
          this.callbacks?.onStdioAck?.(ack)

          if (shouldDispatchPendingListDevices) {
            this.pendingListDevicesAfterStop = false
            this.dispatchServerListDevices()
          }

          return
        }

        if (isStdioReadyLine(parsedJson)) {
          this.handleServerReady()
          return
        }

        if (isServerReadyLine(parsedJson)) {
          this.handleServerReady()
          return
        }
      }

      this.callbacks?.onLine?.({
        type: "bodymonitor_output",
        runId: aRunId,
        stream: aStreamName,
        line,
        parsedJson
      })

      if (aStreamName !== "stdout") {
        return
      }

      const device = parseDeviceInfoFromJson(parsedJson)
      if (device === null) {
        return
      }

      this.accumulatedDevices.push(device)
      this.callbacks?.onDevice?.(aRunId, device)
    })
  }

  private async watchExit(aRunId: string, aChild: ChildProcess): Promise<void> {
    let exitCode = 1

    try {
      exitCode = await aChild.exited
    } catch {
      // Keep default exitCode when subprocess termination cannot be observed cleanly.
    }

    if (this.activeRunId !== aRunId) {
      return
    }

    const shouldRestartForPendingListDevices = this.pendingListDevicesAfterRestart
    const callbacks = this.callbacks

    this.callbacks?.onExit?.(aRunId, exitCode)
    this.resetActiveProcess(aRunId)
    this.setState("idle")

    if (shouldRestartForPendingListDevices && callbacks !== null) {
      void this.restartServerForPendingListDevices(callbacks)
    }
  }

  private resetActiveProcess(aRunId: string): void {
    if (this.activeRunId !== aRunId) {
      return
    }

    if (this.keepAliveTimer !== null) {
      clearInterval(this.keepAliveTimer)
      this.keepAliveTimer = null
    }

    this.childProcess = null
    this.activeRunId = null
    this.activeParams = []
    this.accumulatedDevices = []
    this.stdioState = "idle"
    this.pendingListDevicesAfterStop = false
  }
}

