import type { ArchivedLogChartData, BrowserMessage, GnauralScheduleData, LogSessionKind, ReplaySpeed } from '@protocol'
import type { InjectionKey, Plugin, Ref } from 'vue'

export type BodyMonitorConnectionState = 'connecting' | 'connected' | 'disconnected'

export interface BodyMonitorWsService {
  readonly connectionState: Ref<BodyMonitorConnectionState>
  send(message: BrowserMessage): boolean
}

export interface BodyMonitorReplayAdapter {
  readonly isReplayMode: boolean
  readonly replaySessionId: number | null
  readonly replaySessionName: string
  readonly replayKind: LogSessionKind | null
  readonly replayStatus: 'playing' | 'paused' | 'stopped' | 'finished' | null
  readonly replaySpeed: ReplaySpeed
  readonly replayCursorTimestampMs: number | null
  readonly replaySessionStartMs: number | null
  readonly replayAudioSchedule: GnauralScheduleData | null
  readonly replayAudioScheduleStartedAtMs: number | null
  readonly replayChartData: ArchivedLogChartData | null
  readonly replayChartLoading: boolean
  readonly replayChartError: string | null
  readonly replayError: string | null
  startReplay(sessionId: number, timestampMs?: number): boolean
  pauseReplay(): boolean
  seekReplay(timestampMs: number): boolean
  setReplaySpeed(speed: ReplaySpeed): boolean
  getSelectedDeviceLabel(capability: string): string | null
  isDeviceOffline(deviceIdentifier: string | null): boolean
}

export const BODY_MONITOR_WS_KEY: InjectionKey<BodyMonitorWsService> = Symbol('body-monitor-ws')
export const BODY_MONITOR_REPLAY_KEY: InjectionKey<BodyMonitorReplayAdapter> = Symbol('body-monitor-replay')

export function createBodyMonitorPlugin(options: {
  readonly ws: BodyMonitorWsService
  readonly replay: BodyMonitorReplayAdapter
}): Plugin {
  return {
    install(app) {
      app.provide(BODY_MONITOR_WS_KEY, options.ws)
      app.provide(BODY_MONITOR_REPLAY_KEY, options.replay)
    },
  }
}