import { inject } from 'vue'
import { BODY_MONITOR_REPLAY_KEY, type BodyMonitorReplayAdapter } from '../plugin'

export function useReplay(): BodyMonitorReplayAdapter {
  const replay = inject(BODY_MONITOR_REPLAY_KEY)
  if (replay === undefined) {
    throw new Error('BodyMonitor replay adapter has not been provided. Install createBodyMonitorPlugin in the host app before rendering BodyMonitor pages.')
  }

  return replay
}