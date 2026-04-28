<template>
  <div class="device-list">
    <div class="device-list__scroll">
      <template v-if="hasVisibleDevices">
        <section class="device-list__section">
          <div class="device-list__section-header">
            <div class="text-subtitle2">{{ $t('deviceControl.selectedDevicesTitle') }}</div>
            <div class="text-caption text-grey-5">
              {{ $t('deviceControl.selectedDevicesHint') }}
            </div>
          </div>

          <q-list v-if="topListDevices.length > 0" separator>
            <q-item v-for="d in topListDevices" :key="`selected:${d.mac}`">
              <q-item-section>
                <div class="device-list__card-header row items-start justify-between no-wrap">
                  <q-item-label class="device-list__identity device-list__identity--selected row items-center">
                    <code class="text-grey-6">{{ d.mac }}</code>

                    <div v-if="d.capabilities.length > 0" class="device-list__identity-capabilities row items-center">
                      <div
                        v-for="cap in d.capabilities"
                        :key="cap"
                        class="cap-chip cap-chip--identity row inline items-center no-wrap cursor-pointer"
                        @click="onCapabilitySelected(cap, d)"
                      >
                        <q-radio
                          dense
                          :model-value="device.getSelectedMac(cap)"
                          :val="d.mac"
                          @update:model-value="() => onCapabilitySelected(cap, d)"
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
                    </div>

                    <span>{{ d.name || '(no name)' }}</span>
                    <span v-if="showInactiveStatus(d)" class="device-list__status device-list__status--inactive text-caption">
                      {{ $t('deviceControl.inactive') }}
                    </span>
                    <span v-else-if="showOfflineStatus(d)" class="device-list__status device-list__status--offline text-caption">
                      {{ $t('deviceControl.offline') }}
                    </span>
                  </q-item-label>

                  <div class="device-list__card-actions q-ml-md">
                    <q-btn
                      flat
                      dense
                      :color="showInactiveStatus(d) ? 'positive' : 'warning'"
                      :icon="showInactiveStatus(d) ? 'play_arrow' : 'pause_circle'"
                      :label="showInactiveStatus(d) ? $t('deviceControl.activateButton') : $t('deviceControl.inactiveButton')"
                      class="device-list__toggle-button"
                      :disable="showInactiveStatus(d) && !device.isMarkedDeviceFound(d.mac)"
                      @click="onToggleDeviceInactive(d.mac, !showInactiveStatus(d))"
                    />

                    <q-btn
                      flat
                      dense
                      color="negative"
                      icon="delete"
                      :label="$t('deviceControl.removeButton')"
                      class="device-list__remove-button"
                      @click="onRemoveMarkedDevice(d.mac)"
                    />
                  </div>
                </div>

                <q-item-label
                  caption
                  style="font-size: 0.75rem"
                  class="device-list__device-meta text-grey-6 q-mt-xs"
                >
                  {{ d.type }}<template v-if="d.comPort"> · {{ d.comPort }}</template>
                </q-item-label>

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
                      <FieldHelpText :text="$t('breath.minDeltaDescription')" />
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
                      <FieldHelpText :text="$t('breath.maxRrDescription')" />
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
                  <div class="device-list__connect-timeout-item">
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
                    <FieldHelpText :text="$t('deviceControl.connectTimeoutSecDescription')" />
                  </div>

                  <div v-if="showEegStaleThreshold(d)" class="device-list__connect-timeout-item">
                    <q-input
                      type="number"
                      dense
                      outlined
                      hide-bottom-space
                      min="1"
                      :model-value="device.getEegStaleSec(d.mac)"
                      :label="$t('deviceControl.eegStaleSec')"
                      @update:model-value="(value) => updateEegStaleThreshold(d.mac, value)"
                    />
                    <FieldHelpText :text="$t('deviceControl.eegStaleSecDescription')" />
                  </div>
                </div>
              </q-item-section>
            </q-item>
          </q-list>

          <div v-else class="device-list__empty-state text-grey q-pa-sm">
            {{ $t('deviceControl.selectedDevicesEmpty') }}
          </div>

          <div class="device-list__footer-block q-mt-md">
            <div class="device-list__footer-layout">
              <div class="device-list__footer-action">
                <template v-if="session.isConnecting">
                  <q-btn
                    color="warning"
                    disable
                    class="device-list__action-button"
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
                  class="device-list__action-button"
                  @click="onStop"
                />
                <q-btn
                  v-else
                  color="secondary"
                  :label="$t('deviceControl.connectButton')"
                  :disable="isConnectDisabled"
                  class="device-list__action-button"
                  @click="onConnect"
                />
              </div>

            </div>
          </div>
        </section>

        <section v-if="scanDevices.length > 0" class="device-list__section">
          <div class="device-list__section-header">
            <div class="text-subtitle2">{{ $t('deviceControl.availableDevicesTitle') }}</div>
            <div class="text-caption text-grey-5">
              {{ $t('deviceControl.availableDevicesHint') }}
            </div>
          </div>

          <q-list separator>
            <q-item v-for="d in scanDevices" :key="`scan:${d.mac}`">
              <q-item-section>
                <div class="device-list__card-header row items-start justify-between no-wrap">
                  <q-item-label class="device-list__identity row items-center no-wrap">
                    <code class="text-grey-6">{{ d.mac }}</code>
                    <span>{{ d.name || '(no name)' }}</span>
                  </q-item-label>

                  <q-btn
                    flat
                    dense
                    color="secondary"
                    icon="playlist_add"
                    :label="$t('deviceControl.addButton')"
                    class="device-list__add-button q-ml-md"
                    @click="onRememberFoundDevice(d)"
                  />
                </div>

                <div
                  v-if="d.capabilities.length > 0"
                  class="q-my-xs row q-gutter-xs"
                >
                  <div
                    v-for="cap in d.capabilities"
                    :key="cap"
                    class="device-list__capability-badge row inline items-center no-wrap"
                  >
                    <q-icon
                      :name="meta(cap).icon"
                      :color="meta(cap).color"
                      size="xs"
                      class="q-mr-xs"
                    />
                    <span class="text-caption">{{ $t(`capability.${cap}`) }}</span>
                  </div>
                </div>

                <q-item-label
                  caption
                  style="font-size: 0.75rem"
                  class="text-grey-6"
                >
                  {{ d.type }}<template v-if="d.comPort"> · {{ d.comPort }}</template>
                </q-item-label>
              </q-item-section>
            </q-item>
          </q-list>
        </section>
      </template>

      <div v-else-if="showNoDevicesMessage" class="text-grey q-pa-sm">
        {{ $t('deviceControl.noDevices') }}
      </div>
      <div v-else-if="showPressScanMessage" class="text-grey q-pa-sm">
        {{ $t('deviceControl.pressScan') }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import type { DeviceInfo } from '@protocol'
import FieldHelpText from './FieldHelpText.vue'
import {
  useDeviceStore,
  capabilityMeta,
  capabilityCliParam,
  DEFAULT_BREATH_MIN_DELTA_MS,
  DEFAULT_BREATH_MAX_RR_MS,
} from '../stores/device'
import { useSessionStore } from '../stores/session'
import { useWs } from '../composables/use-ws'
import { buildBodyMonitorCommandLine } from '../services/command-line'

const device = useDeviceStore()
const session = useSessionStore()
const { send } = useWs()
const router = useRouter()

const topListDevices = computed<readonly DeviceInfo[]>(() => device.topListDevices)
const scanDevices = computed<readonly DeviceInfo[]>(() => device.scanDevices)
const hasVisibleDevices = computed(() => topListDevices.value.length > 0 || scanDevices.value.length > 0)
const isConnectDisabled = computed(() => !session.canStart || Object.keys(device.connectTargets).length === 0)
const showStopButton = computed(() => session.bodyMonitorState === 'running' && !session.isConnecting)
const showNoDevicesMessage = computed(() => {
  return session.scanDone && topListDevices.value.length === 0 && scanDevices.value.length === 0
})
const showPressScanMessage = computed(() => {
  if (hasVisibleDevices.value) {
    return false
  }

  return !session.isScanning && !session.scanDone
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

function showInactiveStatus(deviceInfo: DeviceInfo): boolean {
  return device.isDeviceInactive(deviceInfo.mac)
}

function showOfflineStatus(deviceInfo: DeviceInfo): boolean {
  return !device.isDeviceInactive(deviceInfo.mac) && selectedCaps(deviceInfo).some(isSelectedCapabilityOffline)
}

function onCapabilitySelected(capability: string, deviceInfo: DeviceInfo) {
  device.setMarkedDeviceCapabilityActive(capability, deviceInfo.mac, true)
}

function onRememberFoundDevice(deviceInfo: DeviceInfo) {
  device.rememberFoundDevice(deviceInfo)
}

function onToggleDeviceInactive(mac: string, inactive: boolean) {
  device.setDeviceInactive(mac, inactive)
}

function onRemoveMarkedDevice(mac: string) {
  device.removeMarkedDevice(mac)
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

  if (Object.keys(device.connectTargets).length === 0) {
    return
  }

  for (const [cap, paramName] of Object.entries(capabilityCliParam)) {
    const mac = device.getConnectableMac(cap)
    if (mac) params.push(`${paramName}=${mac}`)
  }

  const ecgMac = device.getConnectableMac('ecg')
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

  const eegMac = device.getConnectableMac('eeg')
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
  --device-list-control-width: clamp(12rem, 24vw, 16.25rem);
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

.device-list__identity--selected {
  flex-wrap: wrap;
  min-width: 0;
}

.device-list__identity-capabilities {
  gap: 8px;
  min-width: 0;
}

.device-list__section + .device-list__section {
  margin-top: 20px;
}

.device-list__section-header {
  display: flex;
  flex-direction: column;
  gap: 4px;
  margin-bottom: 8px;
}

.device-list__card-header {
  gap: 12px;
}

.device-list__status {
  border: 1px solid rgba(148, 163, 184, 0.28);
  border-radius: 999px;
  line-height: 1;
  margin-left: auto;
  padding: 4px 8px;
}

.device-list__status--inactive {
  background: rgba(234, 179, 8, 0.12);
  color: rgba(253, 224, 71, 0.95);
}

.device-list__status--offline {
  background: rgba(100, 116, 139, 0.16);
  color: rgba(226, 232, 240, 0.92);
}

.device-list__remove-button {
  align-self: flex-start;
}

.device-list__toggle-button,
.device-list__add-button {
  align-self: flex-start;
}

.device-list__card-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: flex-end;
}

.device-list__empty-state {
  background: rgba(255, 255, 255, 0.03);
  border: 1px dashed rgba(148, 163, 184, 0.18);
  border-radius: 10px;
}

.device-list__device-meta {
  overflow-wrap: anywhere;
}

.device-list__connect-timeout {
  align-items: flex-start;
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}

.device-list__connect-timeout-item {
  display: flex;
  flex-direction: column;
  flex: 0 1 var(--device-list-control-width);
  gap: 8px;
  min-width: min(100%, 12rem);
  width: min(100%, var(--device-list-control-width));
}

.device-list__action-button {
  min-width: 180px;
}

.device-list__footer-block {
  background: rgba(15, 23, 42, 0.55);
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 14px;
  padding: 14px;
}

.device-list__footer-layout {
  align-items: flex-start;
  display: flex;
  flex-wrap: wrap;
  gap: 12px 16px;
  justify-content: space-between;
}

.device-list__footer-action {
  display: flex;
  flex: 0 0 auto;
}

.cap-chip {
  background: rgba(255, 255, 255, 0.07);
  border-radius: 8px;
  padding: 2px 8px 2px 2px;
}

.cap-chip--identity {
  margin: 0;
}

.device-list__capability-badge {
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(148, 163, 184, 0.14);
  border-radius: 8px;
  padding: 4px 10px;
}

.device-list__compact-row {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 10px 14px;
  justify-content: space-between;
}

.device-list__compact-badges,
.device-list__compact-actions {
  align-items: center;
  min-width: 0;
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
  align-items: flex-start;
  display: flex;
  flex: 0 1 var(--device-list-control-width);
  flex-direction: column;
  gap: 12px;
  max-width: var(--device-list-control-width);
  min-width: min(100%, 12rem);
}

.breath-settings__field {
  display: flex;
  flex-direction: column;
  gap: 8px;
  width: min(100%, var(--device-list-control-width));
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
  .breath-settings__layout {
    flex-wrap: wrap;
  }

  .breath-settings__controls {
    flex-basis: var(--device-list-control-width);
    max-width: var(--device-list-control-width);
    min-width: min(100%, 12rem);
  }

  .breath-settings__visual,
  .breath-settings__notes {
    flex-basis: calc(50% - 9px);
    min-width: 280px;
  }
}

@media (max-width: 768px) {
  .device-list__card-header {
    flex-direction: column;
  }

  .device-list__card-actions {
    justify-content: flex-start;
  }

  .device-list__footer-layout {
    flex-direction: column;
  }

  .device-list__footer-action {
    max-width: none;
    min-width: 0;
    width: 100%;
  }

  .device-list__action-button {
    min-width: 0;
    width: 100%;
  }

  .device-list__compact-row {
    align-items: flex-start;
    flex-direction: column;
  }

  .breath-settings__layout {
    flex-direction: column;
  }

  .breath-settings__controls {
    flex-basis: auto;
    max-width: var(--device-list-control-width);
    min-width: min(100%, 12rem);
    width: min(100%, var(--device-list-control-width));
  }

  .breath-settings__visual,
  .breath-settings__notes {
    flex-basis: auto;
    min-width: 0;
    width: 100%;
  }
}
</style>
