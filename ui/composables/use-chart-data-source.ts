import { computed } from 'vue'
import { useSessionStore } from '../stores/session'

export function useChartDataSource() {
  const session = useSessionStore()

  const liveChartData = computed(() => session.chartData)
  const activeChartData = computed(() => session.chartData)

  return {
    activeChartData,
    liveChartData,
  }
}