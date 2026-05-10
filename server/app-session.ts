import { ProcessManager } from "./process-manager"
import type { ProcessManagerCallbacks, ProcessStateSnapshot, StartResult } from "./process-manager"
import type { BodyMonitorEegDiagnosticsEvent, BodyMonitorPingResultEvent } from "./protocol"

export type ManagedAppKind = "bodymonitor" | "gnaural"

export interface AppSession {
  readonly kind: ManagedAppKind
  getState(): ProcessStateSnapshot
  stop(): Promise<boolean>
  startServer(aCallbacks: ProcessManagerCallbacks, aKeepAliveSec?: number, aInitBle?: boolean): Promise<StartResult>
  sendServerListDevices(): void
  pingDevice(aMac: string): Promise<BodyMonitorPingResultEvent>
  diagnoseEeg(aMac: string): Promise<BodyMonitorEegDiagnosticsEvent>
  sendStdioConfigure(aParams: readonly string[]): void
  sendStdioStart(): void
  sendStdioStop(): void
  sendStdioSetParam(aKey: string, aValue: string): void
  sendStdioQuit(): void
}

export function createSession(aKind: ManagedAppKind, aWorkspaceRoot: string): AppSession {
  switch (aKind) {
    case "bodymonitor":
      return new ProcessManager(aWorkspaceRoot)
    case "gnaural":
      throw new Error("Gnaural app session not yet implemented")
  }
}

