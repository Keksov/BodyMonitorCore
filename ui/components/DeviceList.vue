<template>
  <div class="device-list">
    <div class="device-list__scroll">
      <template v-if="visibleDevices.length > 0">
        <q-list separator>
          <q-item v-for="d in visibleDevices" :key="d.mac">
            <q-item-section>
              <q-item-label class="device-list__identity row items-center no-wrap">
                <code class="text-grey-6">{{ d.mac }}</code>
                <span>{{ d.name || '(no name)' }}</span>
                <span v-if="showOfflineStatus(d)" class="device-list__offline text-caption text-grey-5">
                  {{ $t('deviceControl.offline') }}
                </span>
              </q-item-label>

              <div
                v-if="device.browsing ? d.capabilities.length > 0 : selectedCaps(d).length > 0"
                class="q-my-xs row q-gutter-xs"
              >
                <template v-if="device.browsing">
                  <div
                    v-for="cap in d.capabilities"
                    :key="cap"
                    class="cap-chip row inline items-center no-wrap cursor-pointer"
                    @click="device.selectDevice(cap, d.mac)"
                  >
                    <q-radio
                      dense
                      :model-value="device.getSelectedMac(cap)"
                      :val="d.mac"
                      @update:model-value="() => device.selectDevice(cap, d.mac)"
                      class="q-mr-xs"
                    />
                    <q-icon
                      :name="meta(cap).icon"
                      :color="meta(cap).color"
                      size="xs"
                      class="q-mr-xs"
                    />
                    <span class="text-caption">{{ $t(`capability.${cap}`) }}</span>
                  </div>
                </template>

                <template v-else>
                  <div
                    v-for="cap in selectedCaps(d)"
                    :key="cap"
                    class="cap-chip row inline items-center no-wrap"
                  >
                    <q-icon
                      :name="meta(cap).icon"
                      :color="meta(cap).color"
                      size="xs"
                      class="q-mr-xs"
                    />
                    <span class="text-caption">{{ $t(`capability.${cap}`) }}</span>
                  </div>
                </template>
              </div>

              <div
                v-if="showBreathSettings(d)"
                class="breath-settings q-mt-sm q-pa-sm"
              >
                <div class="breath-settings__layout">
                  <div class="breath-settings__controls">
                    <q-toggle
                      :model-value="breathSettingsFor(d.mac).enabled"
                      color="secondary"
                      dense
                      :label="$t('breath.enabled')"
                      @update:model-value="(value) => updateBreathEnabled(d.mac, value)"
                    />
                    <div class="breath-settings__field">
                      <q-input
                        dense
                        outlined
                        hide-bottom-space
                        type="number"
                        :disable="!breathSettingsFor(d.mac).enabled"
                        :model-value="breathSettingsFor(d.mac).minDeltaMs"
                        :label="$t('breath.minDelta')"
                        :step="0.1"
                        min="0.1"
                        @update:model-value="(value) => updateBreathMinDelta(d.mac, value)"
                      />
                      <div class="breath-note breath-note--inline">
                        <div class="breath-note__title">{{ $t('breath.minDelta') }}</div>
                        <div class="breath-note__text">{{ $t('breath.minDeltaDescription') }}</div>
                      </div>
                    </div>
                    <div class="breath-settings__field">
                      <q-input
                        dense
                        outlined
                        hide-bottom-space
                        type="number"
                        :disable="!breathSettingsFor(d.mac).enabled"
                        :model-value="breathSettingsFor(d.mac).maxRrMs"
                        :label="$t('breath.maxRr')"
                        :step="10"
                        min="301"
                        @update:model-value="(value) => updateBreathMaxRr(d.mac, value)"
                      />
                      <div class="breath-note breath-note--inline">
                        <div class="breath-note__title">{{ $t('breath.maxRr') }}</div>
                        <div class="breath-note__text">{{ $t('breath.maxRrDescription') }}</div>
                      </div>
                    </div>
                  </div>

                  <div class="breath-settings__visual">
                    <div class="breath-settings__summary">
                      <div class="breath-settings__summary-line">
                        {{ $t('breath.summary') }}
                      </div>
                      <div class="breath-settings__summary-line breath-settings__summary-line--muted">
                        {{ $t('breath.parameterLink') }}
                      </div>
                    </div>

                    <div class="breath-settings__diagram">
                      <div class="breath-settings__diagram-title text-caption text-grey-5">
                        {{ $t('breath.diagramTitle') }}
                      </div>
                      <svg
                        class="breath-settings__svg"
                        viewBox="0 0 680 230"
                        role="img"
                        aria-hidden="true"
                      >
                        <line x1="28" y1="178" x2="648" y2="178" stroke="#334155" stroke-width="2" />
                        <path
                          d="M 28 166 L 72 166 L 90 164 L 104 52 L 118 166 L 214 166 L 232 164 L 246 92 L 260 166 L 386 166 L 404 164 L 418 66 L 432 166 L 648 166"
                          fill="none"
                          stroke="#6ee7b7"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="4"
                        />
                        <circle cx="104" cy="52" r="6" fill="#f59e0b" />
                        <circle cx="246" cy="92" r="6" fill="#f59e0b" />
                        <circle cx="418" cy="66" r="6" fill="#f59e0b" />
                        <text x="88" y="32" fill="#f8fafc" font-size="16" font-weight="700">R1</text>
                        <text x="230" y="72" fill="#f8fafc" font-size="16" font-weight="700">R2</text>
                        <text x="402" y="46" fill="#f8fafc" font-size="16" font-weight="700">R3</text>
                        <line x1="104" y1="198" x2="246" y2="198" stroke="#60a5fa" stroke-width="3" />
                        <line x1="104" y1="190" x2="104" y2="206" stroke="#60a5fa" stroke-width="3" />
                        <line x1="246" y1="190" x2="246" y2="206" stroke="#60a5fa" stroke-width="3" />
                        <text x="160" y="218" fill="#93c5fd" font-size="15" font-weight="700">RR1</text>
                        <line x1="246" y1="198" x2="418" y2="198" stroke="#f472b6" stroke-width="3" />
                        <line x1="246" y1="190" x2="246" y2="206" stroke="#f472b6" stroke-width="3" />
                        <line x1="418" y1="190" x2="418" y2="206" stroke="#f472b6" stroke-width="3" />
                        <text x="318" y="218" fill="#f9a8d4" font-size="15" font-weight="700">RR2</text>
                        <text x="282" y="26" fill="#cbd5e1" font-size="15" font-weight="700">ΔRR = |RR2 - RR1|</text>
                      </svg>
                    </div>
                  </div>

                  <div class="breath-settings__notes">
                    <div class="breath-note">
                      <div class="breath-note__title">{{ $t('breath.rPeakTitle') }}</div>
                      <div class="breath-note__text">{{ $t('breath.rPeakDescription') }}</div>
                    </div>
                  </div>
                </div>
              </div>

              <div v-if="selectedCaps(d).length > 0" class="device-list__connect-timeout q-mt-sm">
                <q-input
                  type="number"
                  dense
                  outlined
                  hide-bottom-space
                  min="1"
                  :model-value="device.getConnectTimeoutSec(d.mac)"
                  :label="$t('deviceControl.connectTimeoutSec')"
                  @update:model-value="(value) => updateConnectTimeout(d.mac, value)"
                />

                <q-input
                  v-if="showEegStaleThreshold(d)"
                  type="number"
                  dense
                  outlined
                  hide-bottom-space
                  min="1"
                  class="q-mt-sm"
                  :model-value="device.getEegStaleSec(d.mac)"
                  :label="$t('deviceControl.eegStaleSec')"
                  @update:model-value="(value) => updateEegStaleThreshold(d.mac, value)"
                />
              </div>

              <q-item-label
                v-if="device.browsing"
                caption
                style="font-size: 0.75rem"
                class="text-grey-6"
              >
                {{ d.type }}<template v-if="d.comPort"> · {{ d.comPort }}</template>
              </q-item-label>
            </q-item-section>
          </q-item>
        </q-list>
      </template>

      <div v-else-if="showNoDevicesMessage" class="text-grey q-pa-sm">
        {{ $t('deviceControl.noDevices') }}
      </div>
      <div v-else-if="showPressScanMessage" class="text-grey q-pa-sm">
        {{ $t('deviceControl.pressScan') }}
      </div>
    </div>

    <div v-if="showActionFooter" class="device-list__footer">
      <template v-if="session.isConnecting">
        <q-btn
          color="warning"
          disable
          class="device-list__footer-button"
        >
          <q-spinner-hourglass size="xs" class="q-mr-sm" />
          {{ $t('deviceControl.connecting') }}
        </q-btn>
      </template>
      <q-btn
        v-else-if="showStopButton"
        color="negative"
        :label="$t('deviceControl.stopButton')"
        :disable="!session.canStop"
        class="device-list__footer-button"
        @click="onStop"
      />
      <q-btn
        v-else
        color="secondary"
        :label="$t('deviceControl.connectButton')"
        :disable="isConnectDisabled"
        class="device-list__footer-button"
        @click="onConnect"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import type { DeviceInfo } from '@protocol'
import {
  useDeviceStore,
  capabilityMeta,
  capabilityCliParam,
  DEFAULT_BREATH_MIN_DELTA_MS,
  DEFAULT_BREATH_MAX_RR_MS,
} from 'stores/device'
import { useSessionStore } from 'stores/session'
import { useWs } from 'src/composables/use-ws'
import { buildBodyMonitorCommandLine } from '../services/command-line'

const device = useDeviceStore()
const session = useSessionStore()
const { send } = useWs()
const router = useRouter()

const visibleDevices = computed(() => device.browsing ? device.devices : device.selectedDeviceInfos)
const isConnectDisabled = computed(() => !session.canStart || device.selectedDeviceInfos.length === 0)
const showStopButton = computed(() => session.bodyMonitorState === 'running' && !session.isConnecting)
const showActionFooter = computed(() => {
  if (device.browsing) {
    return device.hasDevices && session.scanDone
  }

  return device.selectedDeviceInfos.length > 0
})
const showNoDevicesMessage = computed(() => {
  return device.browsing && session.scanDone && visibleDevices.value.length === 0
})
const showPressScanMessage = computed(() => {
  if (visibleDevices.value.length > 0) {
    return false
  }

  if (device.browsing) {
    return !session.isScanning && !session.scanDone
  }

  return true
})

const fallbackMeta = { icon: 'device_unknown', color: 'grey' }
type NumericInputValue = string | number | null

function meta(cap: string) {
  return capabilityMeta[cap] ?? fallbackMeta
}

function breathSettingsFor(mac: string) {
  return device.getBreathSettings(mac)
}

function showBreathSettings(d: DeviceInfo): boolean {
  return d.capabilities.includes('ecg') && device.isEcgSelected(d.mac)
}

function showEegStaleThreshold(d: DeviceInfo): boolean {
  return d.capabilities.includes('eeg') && device.getSelectedMac('eeg') === d.mac
}

function selectedCaps(d: DeviceInfo): string[] {
  return d.capabilities.filter(
    cap => device.getSelectedMac(cap) === d.mac,
  )
}

function isSelectedCapabilityOffline(capability: string): boolean {
  return session.isDeviceOffline(device.getSelectedMac(capability))
}

function showOfflineStatus(deviceInfo: DeviceInfo): boolean {
  return selectedCaps(deviceInfo).some(isSelectedCapabilityOffline)
}

function parseNumericInput(value: NumericInputValue): number | null {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null
  }

  if (typeof value === 'string') {
    const trimmed = value.trim()
    if (trimmed === '') {
      return null
    }

    const parsed = Number(trimmed)
    return Number.isFinite(parsed) ? parsed : null
  }

  return null
}

function normalizeConnectTimeoutSeconds(value: NumericInputValue): number | null {
  const parsed = parseNumericInput(value)
  if (parsed === null) {
    return null
  }

  return Math.max(1, Math.trunc(parsed))
}

function updateConnectTimeout(mac: string, value: NumericInputValue) {
  const nextValue = normalizeConnectTimeoutSeconds(value)
  if (nextValue === null) {
    return
  }

  if (nextValue !== device.getConnectTimeoutSec(mac)) {
    device.setConnectTimeoutSec(mac, nextValue)
  }
}

function updateEegStaleThreshold(mac: string, value: NumericInputValue) {
  const nextValue = normalizeConnectTimeoutSeconds(value)
  if (nextValue === null) {
    return
  }

  if (nextValue !== device.getEegStaleSec(mac)) {
    device.setEegStaleSec(mac, nextValue)
    applyRuntimeEegParam(mac, '--eeg-stale-sec', String(nextValue))
  }
}

function updateBreathEnabled(mac: string, value: boolean | null) {
  device.setBreathEnabled(mac, value === true)
  applyRuntimeBreathParam(mac, '--breath', value === true ? 'true' : 'false')
}

function updateBreathMinDelta(mac: string, value: NumericInputValue) {
  const parsed = parseNumericInput(value)
  if (parsed === null) {
    return
  }

  device.setBreathMinDelta(mac, parsed)
  applyRuntimeBreathParam(mac, '--breath-min-delta', String(parsed))
}

function updateBreathMaxRr(mac: string, value: NumericInputValue) {
  const parsed = parseNumericInput(value)
  if (parsed === null) {
    return
  }

  device.setBreathMaxRr(mac, parsed)
  applyRuntimeBreathParam(mac, '--breath-rr-max', String(parsed))
}

function applyRuntimeBreathParam(mac: string, key: string, value: string) {
  if (!device.isEcgSelected(mac)) {
    return
  }

  if (session.bodyMonitorState !== 'running' || session.isConnecting || session.isScanning) {
    return
  }

  send({ type: 'bodymonitor_stdio_setparam', key, value })
}

function applyRuntimeEegParam(mac: string, key: string, value: string) {
  if (device.getSelectedMac('eeg') !== mac) {
    return
  }

  if (session.bodyMonitorState !== 'running' || session.isConnecting || session.isScanning) {
    return
  }

  send({ type: 'bodymonitor_stdio_setparam', key, value })
}

function onConnect() {
  const params: string[] = []
  for (const [cap, paramName] of Object.entries(capabilityCliParam)) {
    const mac = device.getSelectedMac(cap)
    if (mac) params.push(`${paramName}=${mac}`)
  }

  const ecgMac = device.getSelectedMac('ecg')
  if (ecgMac !== null) {
    const breathSettings = device.getBreathSettings(ecgMac)
    if (breathSettings.enabled) {
      params.push('--breath')
      if (breathSettings.minDeltaMs !== DEFAULT_BREATH_MIN_DELTA_MS) {
        params.push(`--breath-min-delta=${breathSettings.minDeltaMs}`)
      }
      if (breathSettings.maxRrMs !== DEFAULT_BREATH_MAX_RR_MS) {
        params.push(`--breath-rr-max=${breathSettings.maxRrMs}`)
      }
    }
  }

  const eegMac = device.getSelectedMac('eeg')
  if (eegMac !== null) {
    params.push(`--eeg-stale-sec=${device.getEegStaleSec(eegMac)}`)
  }

  params.push('--log-format=jsonl')
  session.resetOutputState()
  session.beginConnect(buildBodyMonitorCommandLine(params))
  send({ type: 'bodymonitor_stdio_configure', params })
  send({ type: 'bodymonitor_stdio_start' })
}

function onStop() {
  send({ type: 'bodymonitor_stdio_stop' })
}

watch(() => session.connectReadyToken, (token) => {
  if (token <= 0) return
  void router.push('/monitoring')
})
</script>

<style scoped>
.device-list {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
}

.device-list__scroll {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  padding-bottom: 12px;
  padding-right: 4px;
}

.device-list__identity {
  gap: 8px;
}

.device-list__offline {
  margin-left: auto;
}

.device-list__connect-timeout {
  max-width: 240px;
}

.device-list__footer {
  backdrop-filter: blur(10px);
  background: rgba(15, 23, 42, 0.92);
  border-top: 1px solid rgba(148, 163, 184, 0.16);
  flex: 0 0 auto;
  margin-top: 12px;
  padding-top: 12px;
}

.device-list__footer-button {
  min-width: 180px;
}

.cap-chip {
  background: rgba(255, 255, 255, 0.07);
  border-radius: 8px;
  padding: 2px 8px 2px 2px;
}

.breath-settings {
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 10px;
  overflow: hidden;
}

.breath-settings__layout {
  align-items: stretch;
  display: flex;
  gap: 18px;
}

.breath-settings__controls {
  display: flex;
  flex: 0 0 260px;
  flex-direction: column;
  gap: 12px;
  max-width: 260px;
  min-width: 220px;
}

.breath-settings__field {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.breath-settings__visual {
  --breath-visual-width: 480px;
  display: flex;
  flex: 0 0 var(--breath-visual-width);
  flex-direction: column;
  gap: 12px;
  min-width: 0;
  width: min(100%, var(--breath-visual-width));
}

.breath-settings__diagram-title {
  letter-spacing: 0.04em;
  margin-bottom: 10px;
  text-transform: uppercase;
}

.breath-settings__summary {
  background: rgba(15, 23, 42, 0.32);
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 12px;
  max-width: var(--breath-visual-width);
  padding: 10px 12px;
  width: min(100%, var(--breath-visual-width));
}

.breath-settings__summary-line {
  color: rgba(241, 245, 249, 0.92);
  font-size: 0.8rem;
  line-height: 1.45;
}

.breath-settings__summary-line + .breath-settings__summary-line {
  margin-top: 6px;
}

.breath-settings__summary-line--muted {
  color: rgba(191, 219, 254, 0.88);
}

.breath-settings__diagram {
  background:
    radial-gradient(circle at top left, rgba(14, 165, 233, 0.16), transparent 36%),
    linear-gradient(180deg, rgba(15, 23, 42, 0.95), rgba(15, 23, 42, 0.78));
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 12px;
  margin-right: auto;
  max-width: var(--breath-visual-width);
  padding: 12px;
  width: min(100%, var(--breath-visual-width));
}

.breath-settings__svg {
  display: block;
  height: auto;
  width: 100%;
}

.breath-settings__notes {
  display: flex;
  flex: 0 0 320px;
  flex-direction: column;
  gap: 12px;
  min-width: 260px;
}

.breath-note {
  background: rgba(15, 23, 42, 0.35);
  border: 1px solid rgba(148, 163, 184, 0.14);
  border-radius: 10px;
  padding: 10px 12px;
}

.breath-note--inline {
  min-width: 0;
}

.breath-note__title {
  color: rgba(248, 250, 252, 0.94);
  font-size: 0.8rem;
  font-weight: 700;
  margin-bottom: 4px;
}

.breath-note__text {
  color: rgba(203, 213, 225, 0.86);
  font-size: 0.78rem;
  line-height: 1.45;
  white-space: pre-line;
}

@media (max-width: 1024px) {
  .device-list__footer-button {
    min-width: 0;
    width: 100%;
  }

  .breath-settings__layout {
    flex-wrap: wrap;
  }

  .breath-settings__controls {
    flex-basis: 260px;
    max-width: 260px;
    min-width: 220px;
  }

  .breath-settings__visual,
  .breath-settings__notes {
    flex-basis: calc(50% - 9px);
    min-width: 280px;
  }
}

@media (max-width: 768px) {
  .device-list__footer {
    padding-top: 10px;
  }

  .breath-settings__layout {
    flex-direction: column;
  }

  .breath-settings__controls {
    flex-basis: auto;
    max-width: none;
    min-width: 0;
    width: 100%;
  }

  .breath-settings__visual,
  .breath-settings__notes {
    flex-basis: auto;
    min-width: 0;
    width: 100%;
  }
}
</style>
