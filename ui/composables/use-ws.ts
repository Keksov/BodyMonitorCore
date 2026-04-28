import { inject } from 'vue'
import { BODY_MONITOR_WS_KEY, type BodyMonitorWsService } from '../plugin'

export function useWs(): BodyMonitorWsService {
  const ws = inject(BODY_MONITOR_WS_KEY)
  if (ws === undefined) {
    throw new Error('BodyMonitor WS service has not been provided')
  }

  return ws
}