<template>
  <div>
    <div class="text-subtitle1 q-mb-sm">{{ $t('settings.scanBlockTitle') }}</div>
    <div class="row q-gutter-sm items-center q-mb-sm">
      <q-btn
        v-if="session.isScanning"
        color="negative"
        :label="$t('deviceControl.stopButton')"
        @click="onStop"
      />
      <q-btn
        v-else
        color="primary"
        :label="$t('settings.scanButton')"
        :disable="!session.canScan"
        @click="onScan"
      />
    </div>
    <div v-if="session.scanCommandLine" class="cmd-line row items-center no-wrap q-mb-xs">
      <q-btn flat dense round size="xs" icon="content_copy" color="grey-6" class="q-mr-xs" @click="copyCmd">
        <q-tooltip>{{ $t('deviceControl.copyCmd') }}</q-tooltip>
      </q-btn>
      <code class="col text-grey-6 ellipsis">{{ session.scanCommandLine }}</code>
    </div>
    <div v-if="session.isScanning" class="row items-center q-gutter-sm q-mb-xs text-amber-4">
      <q-spinner-hourglass size="sm" />
      <span class="text-caption">{{ progressText }}</span>
    </div>
    <div v-if="statusText" class="text-caption text-grey-5">{{ statusText }}</div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { copyToClipboard, useQuasar } from 'quasar'
import { useSessionStore } from '../stores/session'
import { useDeviceStore } from '../stores/device'
import { useWs } from '../composables/use-ws'

const { t } = useI18n()
const $q = useQuasar()
const session = useSessionStore()
const device = useDeviceStore()
const { send } = useWs()

function onScan() {
  session.resetOutputState()
  device.clearDevices()
  session.beginScan()
  send({ type: 'bodymonitor_server_list_devices' })
}

function onStop() {
  send({ type: 'bodymonitor_stdio_stop' })
}

function copyCmd() {
  copyToClipboard(session.scanCommandLine)
    .then(() => $q.notify({ type: 'positive', message: t('deviceControl.cmdCopied'), timeout: 1500 }))
    .catch(() => { /* ignore */ })
}

const progressText = computed(() => {
  const elapsed = session.scanStatus?.elapsedSec ?? 0
  return t('settings.statusProgress', { seconds: elapsed })
})

const statusText = computed(() => {
  const s = session.scanStatus
  if (!s) return ''
  if (s.translationKey) {
    return t(s.translationKey, s.translationParams ?? {})
  }
  switch (s.key) {
    case 'progress':
      return ''
    case 'found':
      return s.message || t('settings.statusFound', { name: s.identifier, mac: s.mac })
    case 'error':
      return s.message || t('settings.statusError', { name: s.identifier })
    case 'complete':
      return t('settings.statusComplete', { count: s.deviceCount ?? 0 })
    default:
      return s.text ?? ''
  }
})
</script>

<style scoped>
.cmd-line code {
  font-size: 0.7rem;
  line-height: 1.2;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>

