import { defineAsyncComponent } from 'vue'
import messages from './i18n'

const BodyMonitorSettingsTab = defineAsyncComponent(() => import('./settings/BodyMonitorSettingsTab.vue'))

export const bodyMonitorModule = {
  id: 'bodymonitor',
  messages,
  routes: [
    {
      name: 'bodymonitor.monitoring',
      path: 'monitoring',
      navLabelKey: 'nav.monitoring',
      component: () => import('./pages/MonitoringPage.vue'),
    },
  ],
  settingsTabs: [
    {
      name: 'devices',
      icon: 'memory',
      labelKey: 'settings.devicesTab',
      component: BodyMonitorSettingsTab,
    },
  ],
} as const