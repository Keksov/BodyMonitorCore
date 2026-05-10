<template>
  <div class="session-controls">
    <div :class="rowClassNames">
      <div v-for="cap in displayCaps" :key="cap" class="session-device text-caption">
        <div
          :class="[
            'session-device__group',
            { 'session-device__group--with-status': hasIntegratedEegStatus(cap) },
          ]"
        >
          <div class="session-device__badge">
            <div class="session-device__primary row items-center no-wrap">
              <q-icon :name="meta(cap).icon" :color="iconColor(cap)" size="xs" />
              <span :class="['session-device__label', lineTextClass(cap)]">{{ $t(`capability.${cap}`) }}</span>
              <span
                v-if="selectedName(cap) !== ''"
                :class="['session-device__name', nameClass(cap)]"
              >
                {{ selectedName(cap) }}
              </span>
              <span v-else-if="selectedMac(cap) === null" class="session-device__name text-grey">
                {{ $t('deviceControl.noDeviceSelected') }}
              </span>
            </div>

            <div v-if="selectedMac(cap) !== null" :class="['session-device__secondary', macClass(cap)]">
              {{ selectedMac(cap) }}
            </div>
          </div>

          <div v-if="hasIntegratedEegStatus(cap)" class="session-device__status-slot">
            <EegConnectionStatusBadge class="session-device__eeg-status" />
          </div>
        </div>

        <div v-if="showOfflineLine(cap)" class="session-device__status text-grey-5">
          {{ $t('deviceControl.offline') }}
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import EegConnectionStatusBadge from './EegConnectionStatusBadge.vue'
import { useDeviceStore, capabilityMeta, capabilityCliParam } from '../stores/device'
import { useSessionStore } from '../stores/session'

const props = withDefaults(defineProps<{
  readonly align?: 'start' | 'end'
}>(), {
  align: 'start',
})

const deviceStore = useDeviceStore()
const sessionStore = useSessionStore()

const displayCaps = Object.keys(capabilityCliParam)
const rowClassNames = computed(() => [
  'session-controls__row',
  'row',
  props.align === 'end' ? 'justify-end' : 'justify-start',
])

const selectedDevicesByCapability = computed(() => {
  const result: Record<string, { name: string; mac: string } | null> = {}

  for (const cap of displayCaps) {
    const mac = deviceStore.getSelectedMac(cap)
    if (mac === null) {
      result[cap] = null
      continue
    }

    const deviceInfo = deviceStore.selectedDeviceInfos.find((entry) => {
      return entry.mac === mac && entry.capabilities.includes(cap)
    })

    result[cap] = {
      name: deviceInfo?.name?.trim() ?? '',
      mac,
    }
  }

  return result
})

function meta(cap: string) {
  return capabilityMeta[cap] ?? { icon: 'device_unknown', color: 'grey' }
}

function selectedMac(cap: string): string | null {
  return selectedDevicesByCapability.value[cap]?.mac ?? null
}

function selectedName(cap: string): string {
  return selectedDevicesByCapability.value[cap]?.name ?? ''
}

function isOffline(cap: string): boolean {
  const value = selectedMac(cap)
  return sessionStore.isDeviceOffline(value)
}

function hasIntegratedEegStatus(cap: string): boolean {
  return cap === 'eeg' && selectedMac(cap) !== null
}

function showOfflineLine(cap: string): boolean {
  return cap !== 'eeg' && selectedMac(cap) !== null && isOffline(cap)
}

function iconColor(cap: string): string {
  return isOffline(cap) ? 'grey-5' : meta(cap).color
}

function lineTextClass(cap: string): string {
  return isOffline(cap) ? 'text-grey-5' : ''
}

function nameClass(cap: string): string {
  return isOffline(cap) ? 'text-grey-5' : `text-${meta(cap).color}`
}

function macClass(cap: string): string {
  return isOffline(cap) ? 'text-grey-5' : 'text-grey-4'
}
</script>

<style scoped>
.session-controls {
  min-width: 0;
}

.session-controls__row {
  gap: 12px 16px;
  min-width: 0;
}

.session-device {
  flex: 0 1 auto;
  max-width: 100%;
  min-width: 0;
}

.session-device__group {
  align-items: stretch;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 12px;
  display: flex;
  max-width: 100%;
  min-width: 0;
  overflow: hidden;
}

.session-device__badge {
  display: flex;
  flex: 1 1 auto;
  flex-direction: column;
  justify-content: center;
  min-width: 0;
  padding: 8px 12px;
}

.session-device__primary {
  gap: 4px;
  min-width: 0;
}

.session-device__label {
  flex: 0 0 auto;
}

.session-device__name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.session-device__secondary {
  font-family: monospace;
  margin-top: 2px;
  min-width: 0;
  padding-left: 18px;
}

.session-device__status-slot {
  align-items: center;
  background: rgba(255, 255, 255, 0.05);
  border-left: 1px solid rgba(255, 255, 255, 0.12);
  display: flex;
  min-width: 0;
  padding: 8px 12px;
}

.session-device__eeg-status {
  min-width: 0;
}

.session-device__status {
  padding-top: 4px;
  padding-left: 18px;
}

@media (max-width: 899px) {
  .session-controls__row {
    gap: 8px 10px;
    width: 100%;
  }

  .session-device {
    flex: 1 1 100%;
  }

  .session-device__group {
    width: 100%;
  }
}

@media (max-width: 599px) {
  .session-device__group--with-status {
    flex-direction: column;
  }

  .session-device__status-slot {
    border-left: 0;
    border-top: 1px solid rgba(255, 255, 255, 0.12);
    justify-content: flex-start;
  }
}
</style>
