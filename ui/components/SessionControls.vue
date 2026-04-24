<template>
  <div class="session-controls">
    <div :class="rowClassNames">
      <div v-for="cap in displayCaps" :key="cap" class="session-device text-caption">
        <div class="session-device__line row items-center no-wrap">
          <q-icon :name="meta(cap).icon" :color="iconColor(cap)" size="xs" />
          <span :class="lineTextClass(cap)">{{ $t(`capability.${cap}`) }}:</span>
          <span v-if="selectedValue(cap)" :class="valueClass(cap)">
            {{ selectedValue(cap) }}
          </span>
          <span v-else class="text-grey">{{ $t('deviceControl.noDeviceSelected') }}</span>
        </div>
        <div v-if="selectedValue(cap) && isOffline(cap)" class="session-device__status text-grey-5">
          {{ $t('deviceControl.offline') }}
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useDeviceStore, capabilityMeta, capabilityCliParam } from 'stores/device'
import { useSessionStore } from 'stores/session'
import { useReplayStore } from 'stores/replay'

const props = withDefaults(defineProps<{
  readonly align?: 'start' | 'end'
}>(), {
  align: 'start',
})

const deviceStore = useDeviceStore()
const sessionStore = useSessionStore()
const replayStore = useReplayStore()

const displayCaps = Object.keys(capabilityCliParam)
const rowClassNames = computed(() => [
  'session-controls__row',
  'row',
  'q-gutter-lg',
  props.align === 'end' ? 'justify-end' : 'justify-start',
])

function meta(cap: string) {
  return capabilityMeta[cap] ?? { icon: 'device_unknown', color: 'grey' }
}

function selectedValue(cap: string): string | null {
  if (replayStore.isReplayMode) {
    return replayStore.getSelectedDeviceLabel(cap)
  }

  return deviceStore.getSelectedMac(cap)
}

function isOffline(cap: string): boolean {
  const value = selectedValue(cap)
  return replayStore.isReplayMode ? replayStore.isDeviceOffline(value) : sessionStore.isDeviceOffline(value)
}

function iconColor(cap: string): string {
  return isOffline(cap) ? 'grey-5' : meta(cap).color
}

function lineTextClass(cap: string): string {
  return isOffline(cap) ? 'text-grey-5' : ''
}

function valueClass(cap: string): string {
  return isOffline(cap) ? 'text-grey-5' : `text-${meta(cap).color}`
}
</script>

<style scoped>
.session-controls {
  min-width: 0;
}

.session-controls__row {
  min-width: 0;
}

.session-device {
  min-width: 0;
}

.session-device__line {
  gap: 4px;
}

.session-device__status {
  padding-left: 18px;
}
</style>
