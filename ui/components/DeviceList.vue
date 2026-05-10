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
                    <q-btn
                      flat
                      dense
                      no-caps
                      padding="2px 4px"
                      :color="isDeviceCardCollapsed(d.mac) ? 'grey-5' : 'secondary'"
                      :disable="!hasDeviceSettings(d)"
                      :aria-label="$t(isDeviceCardCollapsed(d.mac) ? 'deviceControl.expandDetailsButton' : 'deviceControl.collapseDetailsButton')"
                      :title="$t(isDeviceCardCollapsed(d.mac) ? 'deviceControl.expandDetailsButton' : 'deviceControl.collapseDetailsButton')"
                      :class="[
                        'device-list__collapse-button',
                        { 'device-list__collapse-button--expanded': !isDeviceCardCollapsed(d.mac) },
                      ]"
                      @click="onToggleDeviceCardCollapsed(d.mac)"
                    >
                      <span class="device-list__collapse-button-content row inline items-center no-wrap">
                        <q-icon name="settings" size="16px" />
                        <q-icon :name="isDeviceCardCollapsed(d.mac) ? 'keyboard_arrow_right' : 'keyboard_arrow_down'" size="16px" />
                      </span>
                    </q-btn>

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

                    <div class="device-list__identity-title row items-center">
                      <span class="device-list__identity-name">{{ d.name || '(no name)' }}</span>
                      <q-btn
                        v-if="showAttentionCalibrationButton(d)"
                        outline
                        dense
                        no-caps
                        padding="4px 10px"
                        :disable="!canOpenAttentionCalibration(d)"
                        :color="getCalibrationButtonColor(d.mac)"
                        icon="psychology"
                        :label="$t('calibration.actions.open')"
                        class="device-list__calibration-button device-list__calibration-button--header"
                        @click="onOpenAttentionCalibration(d)"
                      />
                      <EegConnectionStatusBadge
                        v-if="showSelectedEegConnectionStatus(d)"
                        class="device-list__eeg-status-badge"
                      />
                    </div>
                  </q-item-label>

                  <div class="device-list__card-actions q-ml-md">
                    <q-btn
                      flat
                      dense
                      :color="showInactiveStatus(d) ? 'warning' : 'positive'"
                      :icon="showInactiveStatus(d) ? 'check_box_outline_blank' : 'check_box'"
                      :label="$t('deviceControl.activateButton')"
                      class="device-list__toggle-button"
                      @click="onToggleDeviceInactive(d, !showInactiveStatus(d))"
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

                <q-slide-transition>
                  <div v-show="!isDeviceCardCollapsed(d.mac) && hasDeviceSettings(d)">
                    <div
                      v-if="hasCalibrationResults(d.mac)"
                      class="device-list__calibration-hub q-mt-sm"
                    >
                      <div class="device-list__calibration-cards">
                        <article :class="['device-list__calibration-card', 'device-list__calibration-card--attention', getCalibrationCardStateClass(d.mac, 'attention')]">
                          <div class="device-list__calibration-card-title row items-center no-wrap">
                            <q-icon name="psychology" size="14px" color="secondary" class="q-mr-xs" />
                            <span>{{ $t('calibration.attention.summaryLabel') }}</span>
                          </div>
                          <div class="device-list__calibration-card-date">
                            {{ formatCalibrationSummaryTime(getAttentionCalibrationSummary(d.mac)?.recordedAtMs ?? null) }}
                          </div>
                          <div v-if="getCalibrationCardInvalidReason(d.mac, 'attention') !== null" class="device-list__calibration-card-reason">
                            {{ getCalibrationCardInvalidReason(d.mac, 'attention') }}
                          </div>
                        </article>

                        <article :class="['device-list__calibration-card', 'device-list__calibration-card--relaxation', getCalibrationCardStateClass(d.mac, 'alphaRelaxation')]">
                          <div class="device-list__calibration-card-title row items-center no-wrap">
                            <q-icon name="air" size="14px" color="white" class="q-mr-xs" />
                            <span>{{ $t('calibration.alphaRelaxation.summaryLabel') }}</span>
                          </div>
                          <div class="device-list__calibration-card-time">
                            {{ formatCalibrationSummaryTime(getAlphaRelaxationSummary(d.mac)?.recordedAtMs ?? null) }}
                          </div>
                          <div v-if="getCalibrationCardInvalidReason(d.mac, 'alphaRelaxation') !== null" class="device-list__calibration-card-reason">
                            {{ getCalibrationCardInvalidReason(d.mac, 'alphaRelaxation') }}
                          </div>

                          <div v-if="getAlphaRelaxationSummary(d.mac) !== null" class="device-list__calibration-card-badges">
                            <div class="device-list__calibration-card-badge">
                              {{ $t('calibration.alphaRelaxation.controls.durationLabel') }}: {{ Math.max(1, Math.round((getAlphaRelaxationSummary(d.mac)?.durationSec ?? 0) / 60)) }}
                            </div>
                            <div class="device-list__calibration-card-badge">
                              {{ $t('calibration.alphaRelaxation.status.cycles', { count: getAlphaRelaxationSummary(d.mac)?.cyclesCompleted ?? 0 }) }}
                            </div>
                          </div>
                        </article>

                        <article :class="['device-list__calibration-card', 'device-list__calibration-card--drowse', getCalibrationCardStateClass(d.mac, 'drowse')]">
                          <div class="device-list__calibration-card-title row items-center no-wrap">
                            <q-icon name="bedtime" size="14px" color="blue-grey-3" class="q-mr-xs" />
                            <span>{{ $t('calibration.sleepDrowse.summaryLabel') }}</span>
                          </div>
                          <div class="device-list__calibration-card-time">
                            {{ formatCalibrationSummaryTime(getDrowseCalibrationSummary(d.mac)?.recordedAtMs ?? null) }}
                          </div>
                          <div v-if="getCalibrationCardInvalidReason(d.mac, 'drowse') !== null" class="device-list__calibration-card-reason">
                            {{ getCalibrationCardInvalidReason(d.mac, 'drowse') }}
                          </div>

                          <div v-if="getDrowseCalibrationSummary(d.mac) !== null" class="device-list__calibration-card-badges">
                            <div class="device-list__calibration-card-badge">
                              {{ $t('calibration.sleepDrowse.controls.durationLabel') }}: {{ Math.max(1, Math.round((getDrowseCalibrationSummary(d.mac)?.durationSec ?? 0) / 60)) }}
                            </div>
                          </div>
                        </article>
                      </div>
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

                      <EegDiagnosticsPanel v-if="d.capabilities.includes('eeg')" :mac="d.mac" class="q-mt-xs" />
                    </div>
                  </div>
                </q-slide-transition>
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
                  :label="$t('deviceControl.stopRecordingButton')"
                  :disable="!session.canStop"
                  class="device-list__action-button"
                  @click="onStop"
                />
                <q-btn
                  v-else
                  color="secondary"
                  :label="$t('deviceControl.startRecordingButton')"
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

                  <div class="device-list__card-actions q-ml-md">
                    <span
                      v-if="getScanDeviceStatus(d) !== null"
                      :class="['device-list__status', getScanDeviceStatus(d)?.cssClass, 'text-caption']"
                    >
                      <span
                        :class="[
                          'device-list__status-icon',
                          { 'device-list__status-icon--spinning': getScanDeviceStatus(d)?.animateIcon === true },
                        ]"
                      >
                        <q-icon
                          :name="getScanDeviceStatus(d)?.icon"
                          size="14px"
                        />
                      </span>
                      {{ $t(getScanDeviceStatus(d)?.labelKey ?? 'deviceControl.searching') }}
                    </span>

                    <q-btn
                      flat
                      dense
                      color="secondary"
                      icon="playlist_add"
                      :label="$t('deviceControl.addButton')"
                      class="device-list__add-button"
                      @click="onRememberFoundDevice(d)"
                    />
                  </div>
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

    <calibration-hub-dialog
      :model-value="calibrationDialog.isOpen"
      :initial-mode="calibrationDialog.initialMode"
      :device-mac="calibrationDialog.deviceMac"
      :mode-states="activeCalibrationModeStates"
      :previous-attention-summary="activeCalibrationSummary"
      :previous-alpha-relaxation-summary="activeAlphaRelaxationSummary"
      :previous-drowse-summary="activeDrowseSummary"
      @update:model-value="onCalibrationDialogChange"
      @attention-clear="onAttentionCalibrationCleared"
      @alpha-relaxation-clear="onAlphaRelaxationCleared"
      @drowse-clear="onDrowseCleared"
      @attention-save="onAttentionCalibrationSaved"
      @alpha-relaxation-save="onAlphaRelaxationSaved"
      @drowse-save="onDrowseSaved"
    />

    <q-dialog
      :model-value="reconnectModal.isOpen"
      persistent
    >
      <q-card class="device-list__reconnect-dialog">
        <q-card-section class="row no-wrap items-start q-col-gutter-md">
          <q-spinner-dots size="32px" color="primary" class="q-mt-xs" />
          <div>
            <div class="text-subtitle2">{{ $t('deviceControl.reconnect.title') }}</div>
            <div class="text-body2 q-mt-xs">{{ $t('deviceControl.reconnect.message') }}</div>
          </div>
        </q-card-section>
        <q-card-actions align="right">
          <q-btn flat :label="$t('deviceControl.reconnect.closeButton')" @click="onReconnectModalClose" />
        </q-card-actions>
      </q-card>
    </q-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import type { DeviceInfo } from '@protocol'
import CalibrationHubDialog from './CalibrationHubDialog.vue'
import EegConnectionStatusBadge from './EegConnectionStatusBadge.vue'
import FieldHelpText from './FieldHelpText.vue'
import EegDiagnosticsPanel from './EegDiagnosticsPanel.vue'
import { useEegDiagnosticsStore, type EegDiagnosticsStatusKey } from '../stores/eeg-diagnostics'
import {
  useDeviceStore,
  capabilityMeta,
  type AlphaRelaxationSummary,
  type AttentionCalibrationSummary,
  type DrowseCalibrationSummary,
} from '../stores/device'
import { useBodyMonitorSessionStarter } from '../composables/use-bodymonitor-session-starter'
import { useSessionStore } from '../stores/session'
import { useWs } from '../composables/use-ws'

const device = useDeviceStore()
const eegDiagnostics = useEegDiagnosticsStore()
const session = useSessionStore()
const { send } = useWs()
const { startMonitoring } = useBodyMonitorSessionStarter()
const pendingNavigationOnConnect = ref(false)
const router = useRouter()
const { t } = useI18n()
const PING_RETRY_MS = 3000
const PING_SUCCESS_TTL_MS = 10000
const PING_MIN_REQUEST_INTERVAL_MS = 5000
const calibrationTimeFormatter = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
})
const CALIBRATION_ACTION_ENABLED_STATUSES = new Set<EegDiagnosticsStatusKey>(['ready', 'connected', 'reconnected', 'stale'])

let pingPumpTimer: ReturnType<typeof setInterval> | null = null
let reconnectPingTimer: ReturnType<typeof setInterval> | null = null
const reconnectModal = reactive({
  isOpen: false,
  deviceMac: null as string | null,
  pendingMode: null as 'attention' | 'relaxation' | 'drowse' | null,
})
const calibrationDialog = reactive({
  isOpen: false,
  deviceMac: null as string | null,
  initialMode: null as 'attention' | 'relaxation' | 'drowse' | null,
})

const topListDevices = computed<readonly DeviceInfo[]>(() => device.topListDevices)
const scanDevices = computed<readonly DeviceInfo[]>(() => device.scanDevices)
const hasVisibleDevices = computed(() => topListDevices.value.length > 0 || scanDevices.value.length > 0)
const isConnectDisabled = computed(() => !session.canStart || !device.areAllRequiredConnectTargetsReady)
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
const activeCalibrationSummary = computed(() => {
  return calibrationDialog.deviceMac === null
    ? null
    : device.getAttentionCalibrationSummary(calibrationDialog.deviceMac)
})
const activeAlphaRelaxationSummary = computed(() => {
  return calibrationDialog.deviceMac === null
    ? null
    : device.getAlphaRelaxationSummary(calibrationDialog.deviceMac)
})
const activeDrowseSummary = computed(() => {
  return calibrationDialog.deviceMac === null
    ? null
    : device.getDrowseCalibrationSummary(calibrationDialog.deviceMac)
})
const activeCalibrationModeStates = computed<CalibrationDialogModeStates>(() => {
  if (calibrationDialog.deviceMac === null) {
    return {
      attention: 'pending',
      relaxation: 'pending',
      drowse: 'pending',
    }
  }

  return {
    attention: getCalibrationModeState(calibrationDialog.deviceMac, 'attention'),
    relaxation: getCalibrationModeState(calibrationDialog.deviceMac, 'alphaRelaxation'),
    drowse: getCalibrationModeState(calibrationDialog.deviceMac, 'drowse'),
  }
})

const fallbackMeta = { icon: 'device_unknown', color: 'grey' }
type CalibrationDialogMode = 'attention' | 'relaxation' | 'drowse'
type CalibrationModeVisualState = 'complete' | 'pending'
type CalibrationDialogModeStates = Record<CalibrationDialogMode, CalibrationModeVisualState>
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

function isSelectedEegDevice(d: DeviceInfo): boolean {
  return d.capabilities.includes('eeg') && device.getSelectedMac('eeg') === d.mac
}

function showEegStaleThreshold(d: DeviceInfo): boolean {
  return isSelectedEegDevice(d)
}

function showAttentionCalibrationButton(d: DeviceInfo): boolean {
  return isSelectedEegDevice(d)
}

function showAlphaRelaxationButton(d: DeviceInfo): boolean {
  return isSelectedEegDevice(d)
}

function showSelectedEegConnectionStatus(d: DeviceInfo): boolean {
  return isSelectedEegDevice(d)
}

function getSelectedEegDiagnosticsStatus(deviceInfo: DeviceInfo): EegDiagnosticsStatusKey | null {
  if (!isSelectedEegDevice(deviceInfo)) {
    return null
  }

  return eegDiagnostics.getStatusKey(deviceInfo.mac)
}

function canOpenAttentionCalibration(deviceInfo: DeviceInfo): boolean {
  const statusKey = getSelectedEegDiagnosticsStatus(deviceInfo)
  return statusKey !== null && CALIBRATION_ACTION_ENABLED_STATUSES.has(statusKey)
}

function getCalibrationButtonColor(mac: string): 'positive' | 'warning' {
  return device.getEegCalibrationProfile(mac)?.isComplete === true ? 'positive' : 'warning'
}

function selectedCaps(d: DeviceInfo): string[] {
  return d.capabilities.filter(
    cap => device.getSelectedMac(cap) === d.mac,
  )
}

function hasDeviceSettings(d: DeviceInfo): boolean {
  return selectedCaps(d).length > 0
}

function getAttentionCalibrationSummary(mac: string): AttentionCalibrationSummary | null {
  return device.getAttentionCalibrationSummary(mac)
}

function getAlphaRelaxationSummary(mac: string): AlphaRelaxationSummary | null {
  return device.getAlphaRelaxationSummary(mac)
}

function getDrowseCalibrationSummary(mac: string): DrowseCalibrationSummary | null {
  return device.getDrowseCalibrationSummary(mac)
}

function hasCalibrationResults(mac: string): boolean {
  return (
    getAttentionCalibrationSummary(mac) !== null ||
    getAlphaRelaxationSummary(mac) !== null ||
    getDrowseCalibrationSummary(mac) !== null
  )
}

type CalibrationCardMode = 'attention' | 'alphaRelaxation' | 'drowse'

function hasCalibrationSummaryForMode(mac: string, mode: CalibrationCardMode): boolean {
  switch (mode) {
    case 'attention':
      return getAttentionCalibrationSummary(mac) !== null
    case 'alphaRelaxation':
      return getAlphaRelaxationSummary(mac) !== null
    case 'drowse':
      return getDrowseCalibrationSummary(mac) !== null
    default:
      return false
  }
}

function isCalibrationCardComplete(mac: string, mode: CalibrationCardMode): boolean {
  const profile = device.getEegCalibrationProfile(mac)
  if (profile === null || profile.invalidBands.length > 0) {
    return false
  }

  const completedModes = profile.completedModes

  switch (mode) {
    case 'attention':
      return completedModes.attention === true
    case 'alphaRelaxation':
      return completedModes.alphaRelaxation === true
    case 'drowse':
      return completedModes.drowse === true
    default:
      return false
  }
}

function getCalibrationCardInvalidReason(mac: string, mode: CalibrationCardMode): string | null {
  if (isCalibrationCardComplete(mac, mode)) {
    return null
  }

  if (!hasCalibrationSummaryForMode(mac, mode)) {
    return t('calibration.cardReason.notRun')
  }

  const profile = device.getEegCalibrationProfile(mac)
  if (profile === null) {
    return t('calibration.cardReason.profileMissing')
  }

  if (profile.invalidBands.length > 0) {
    return t('calibration.cardReason.invalidBands')
  }

  return t('calibration.cardReason.captureMissing')
}

function getCalibrationModeState(mac: string, mode: CalibrationCardMode): CalibrationModeVisualState {
  return isCalibrationCardComplete(mac, mode)
    ? 'complete'
    : 'pending'
}

function getCalibrationCardStateClass(mac: string, mode: CalibrationCardMode): string {
  return getCalibrationModeState(mac, mode) === 'complete'
    ? 'device-list__calibration-card--complete'
    : 'device-list__calibration-card--pending'
}

function formatCalibrationSummaryTime(recordedAtMs: number | null): string {
  if (recordedAtMs === null) {
    return t('calibration.notRunYet')
  }

  return calibrationTimeFormatter.format(new Date(recordedAtMs))
}

function calibrationSummaryMetrics(mac: string): string {
  const summary = getAttentionCalibrationSummary(mac)
  if (summary === null) {
    return ''
  }

  return deviceSummaryMetrics(summary)
}

function alphaRelaxationSummaryMetrics(mac: string): string {
  const summary = getAlphaRelaxationSummary(mac)
  if (summary === null) {
    return ''
  }

  return t('calibration.alphaRelaxation.summaryMetrics', {
    minutes: Math.max(1, Math.round(summary.durationSec / 60)),
    cycles: summary.cyclesCompleted,
  })
}

function deviceSummaryMetrics(summary: AttentionCalibrationSummary): string {
  return t('calibration.attention.summaryMetrics', {
    count: summary.completedTargetCount,
    errors: summary.errorCount,
  })
}


function isSelectedCapabilityOffline(capability: string): boolean {
  return session.isDeviceOffline(device.getSelectedMac(capability))
}

function showInactiveStatus(deviceInfo: DeviceInfo): boolean {
  return device.isDeviceInactive(deviceInfo.mac)
}

function isDeviceCardCollapsed(mac: string): boolean {
  return device.isDeviceCardCollapsed(mac)
}

function isRuntimeSessionActive(): boolean {
  return session.bodyMonitorState === 'running'
    || session.bodyMonitorState === 'starting'
    || session.isConnecting
}

function getUnifiedDeviceStatus(deviceInfo: DeviceInfo): { cssClass: string; icon: string; labelKey: string; animateIcon?: boolean } {
  const runtimeState = session.getDeviceConnectionState(deviceInfo.mac)
  const runtimeSessionActive = isRuntimeSessionActive()
  const requiresPing = device.requiredPingMacs.includes(deviceInfo.mac)
  if (requiresPing) {
    if (runtimeState === 'offline') {
      return { cssClass: 'device-list__status--offline', icon: 'link_off', labelKey: 'deviceControl.offline' }
    }

    const hasFreshPingSuccess = device.isPingReady(deviceInfo.mac)
      && device.isPingSuccessFresh(deviceInfo.mac, PING_SUCCESS_TTL_MS)

    if (hasFreshPingSuccess) {
      return { cssClass: 'device-list__status--online', icon: 'check_circle', labelKey: 'deviceControl.connected' }
    }

    if (device.isPingInProgress(deviceInfo.mac)) {
      return { cssClass: 'device-list__status--searching', icon: 'sync', labelKey: 'deviceControl.checking', animateIcon: true }
    }

    if (runtimeSessionActive && runtimeState === 'online') {
      return { cssClass: 'device-list__status--online', icon: 'check_circle', labelKey: 'deviceControl.connected' }
    }

    return { cssClass: 'device-list__status--offline', icon: 'link_off', labelKey: 'deviceControl.offline' }
  }

  if (runtimeSessionActive && runtimeState === 'online') {
    return { cssClass: 'device-list__status--online', icon: 'check_circle', labelKey: 'deviceControl.connected' }
  }

  if (runtimeState === 'offline') {
    return { cssClass: 'device-list__status--offline', icon: 'link_off', labelKey: 'deviceControl.offline' }
  }

  const found = device.isMarkedDeviceFound(deviceInfo.mac)
  if (session.isScanning || found) {
    return found
      ? { cssClass: 'device-list__status--found', icon: 'check_circle_outline', labelKey: 'deviceControl.found' }
      : { cssClass: 'device-list__status--searching', icon: 'sync', labelKey: 'deviceControl.searching', animateIcon: true }
  }
  return { cssClass: 'device-list__status--offline', icon: 'link_off', labelKey: 'deviceControl.offline' }
}

function getScanDeviceStatus(deviceInfo: DeviceInfo): { cssClass: string; icon: string; labelKey: string; animateIcon?: boolean } | null {
  const status = device.getScanProbeStatus(deviceInfo.mac)
  if (status === null) {
    return null
  }

  switch (status.state) {
    case 'queued':
      return { cssClass: 'device-list__status--searching', icon: 'sync', labelKey: 'deviceControl.scanQueued', animateIcon: true }
    case 'probing':
      return { cssClass: 'device-list__status--searching', icon: 'sync', labelKey: 'deviceControl.scanProbing', animateIcon: true }
    case 'complete':
      return { cssClass: 'device-list__status--found', icon: 'check_circle_outline', labelKey: 'deviceControl.scanComplete' }
    case 'not_connectable':
      return { cssClass: 'device-list__status--offline', icon: 'portable_wifi_off', labelKey: 'deviceControl.scanNotConnectable' }
    case 'failed':
      return { cssClass: 'device-list__status--offline', icon: 'error_outline', labelKey: 'deviceControl.scanFailed' }
    case 'cancelled':
      return { cssClass: 'device-list__status--offline', icon: 'cancel', labelKey: 'deviceControl.scanCancelled' }
    default:
      return null
  }
}

function onCapabilitySelected(capability: string, deviceInfo: DeviceInfo) {
  device.setMarkedDeviceCapabilityActive(capability, deviceInfo.mac, true)
}

function onRememberFoundDevice(deviceInfo: DeviceInfo) {
  device.rememberFoundDevice(deviceInfo)
}

function onToggleDeviceInactive(deviceInfo: DeviceInfo, inactive: boolean) {
  device.setDeviceInactive(deviceInfo.mac, inactive)
  if (!inactive) {
    for (const cap of deviceInfo.capabilities) {
      device.setMarkedDeviceCapabilityActive(cap, deviceInfo.mac, true)
    }
  }
}

function onToggleDeviceCardCollapsed(mac: string) {
  device.setDeviceCardCollapsed(mac, !device.isDeviceCardCollapsed(mac))
}

function openReconnectModal(deviceInfo: DeviceInfo, pendingMode: 'attention' | 'relaxation' | 'drowse' | null): void {
  reconnectModal.isOpen = true
  reconnectModal.deviceMac = deviceInfo.mac
  reconnectModal.pendingMode = pendingMode
  startReconnectPingLoop(deviceInfo.mac)
}

function closeReconnectModal(): void {
  stopReconnectPingLoop()
  reconnectModal.isOpen = false
  reconnectModal.deviceMac = null
  reconnectModal.pendingMode = null
}

function onReconnectModalClose(): void {
  closeReconnectModal()
}

function onReconnectModalDeviceConnected(): void {
  const deviceMac = reconnectModal.deviceMac
  const pendingMode = reconnectModal.pendingMode
  closeReconnectModal()
  if (deviceMac !== null) {
    calibrationDialog.isOpen = true
    calibrationDialog.deviceMac = deviceMac
    calibrationDialog.initialMode = pendingMode
  }
}

function startReconnectPingLoop(mac: string): void {
  stopReconnectPingLoop()
  tryReconnectPing(mac)
  reconnectPingTimer = setInterval(() => {
    tryReconnectPing(mac)
  }, PING_RETRY_MS)
}

function stopReconnectPingLoop(): void {
  if (reconnectPingTimer === null) {
    return
  }

  clearInterval(reconnectPingTimer)
  reconnectPingTimer = null
}

function tryReconnectPing(mac: string): void {
  if (session.isConnecting || session.bodyMonitorState !== 'idle') {
    return
  }

  if (device.isPingInProgress(mac)) {
    return
  }

  if (!device.canSchedulePing(mac, PING_MIN_REQUEST_INTERVAL_MS)) {
    return
  }

  if (send({ type: 'bodymonitor_server_ping_device', mac })) {
    device.markPingPending(mac)
  }
}

function onOpenAttentionCalibration(deviceInfo: DeviceInfo) {
  if (!showAttentionCalibrationButton(deviceInfo) || !canOpenAttentionCalibration(deviceInfo)) {
    return
  }

  calibrationDialog.isOpen = true
  calibrationDialog.deviceMac = deviceInfo.mac
  calibrationDialog.initialMode = null
}

function onCalibrationDialogChange(value: boolean) {
  calibrationDialog.isOpen = value
  if (value) {
    return
  }

  calibrationDialog.deviceMac = null
  calibrationDialog.initialMode = null
}

function onAttentionCalibrationSaved(summary: AttentionCalibrationSummary) {
  if (calibrationDialog.deviceMac === null) {
    return
  }

  device.setAttentionCalibrationSummary(calibrationDialog.deviceMac, summary)
}

function onAttentionCalibrationCleared() {
  if (calibrationDialog.deviceMac === null) {
    return
  }

  device.clearAttentionCalibrationSummary(calibrationDialog.deviceMac)
}

function onOpenAlphaRelaxation(deviceInfo: DeviceInfo) {
  if (!showAlphaRelaxationButton(deviceInfo)) {
    return
  }

  calibrationDialog.isOpen = true
  calibrationDialog.deviceMac = deviceInfo.mac
  calibrationDialog.initialMode = 'relaxation'
}

function onAlphaRelaxationSaved(summary: AlphaRelaxationSummary) {
  if (calibrationDialog.deviceMac === null) {
    return
  }

  device.setAlphaRelaxationSummary(calibrationDialog.deviceMac, summary)
}

function onAlphaRelaxationCleared() {
  if (calibrationDialog.deviceMac === null) {
    return
  }

  device.clearAlphaRelaxationSummary(calibrationDialog.deviceMac)
}

function onDrowseSaved(summary: DrowseCalibrationSummary) {
  if (calibrationDialog.deviceMac === null) {
    return
  }

  device.setDrowseCalibrationSummary(calibrationDialog.deviceMac, summary)
}

function onDrowseCleared() {
  if (calibrationDialog.deviceMac === null) {
    return
  }

  device.clearDrowseCalibrationSummary(calibrationDialog.deviceMac)
}

function onRemoveMarkedDevice(mac: string) {
  device.removeMarkedDevice(mac)
}

function syncPingRequests() {
  const requiredMacs = new Set(device.requiredPingMacs)

  for (const topListDevice of topListDevices.value) {
    if (!requiredMacs.has(topListDevice.mac)) {
      device.clearPingState(topListDevice.mac)
    }
  }

  if (session.isConnecting || session.bodyMonitorState !== 'idle') {
    return
  }

  for (const mac of requiredMacs) {
    if (device.isPingInProgress(mac)) {
      continue
    }

    const shouldRefresh = !device.isPingSuccessFresh(mac, PING_SUCCESS_TTL_MS)
      || device.getPingState(mac) !== 'reachable'
    if (!shouldRefresh) {
      continue
    }

    if (!device.canSchedulePing(mac, PING_MIN_REQUEST_INTERVAL_MS)) {
      continue
    }

    if (send({ type: 'bodymonitor_server_ping_device', mac })) {
      device.markPingPending(mac)
    }
  }
}

function startPingPump() {
  syncPingRequests()
  if (pingPumpTimer !== null) {
    return
  }

  pingPumpTimer = setInterval(() => {
    syncPingRequests()
  }, PING_RETRY_MS)
}

function stopPingPump() {
  if (pingPumpTimer === null) {
    return
  }

  clearInterval(pingPumpTimer)
  pingPumpTimer = null
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
  if (!device.areAllRequiredConnectTargetsReady) {
    pendingNavigationOnConnect.value = false
    return
  }

  pendingNavigationOnConnect.value = startMonitoring()
}

function onStop() {
  pendingNavigationOnConnect.value = false
  send({ type: 'bodymonitor_stdio_stop' })
}

watch(() => [
  JSON.stringify(device.selectedDevices),
  JSON.stringify(device.inactiveDeviceMacs),
  topListDevices.value.map((deviceInfo) => deviceInfo.mac).join('|'),
  session.bodyMonitorState,
  session.isConnecting ? '1' : '0',
].join('|'), () => {
  syncPingRequests()
}, { immediate: true })

watch(() => session.connectReadyToken, (token) => {
  if (token <= 0 || !pendingNavigationOnConnect.value) {
    return
  }

  pendingNavigationOnConnect.value = false
  void router.push('/monitoring')
})

watch(() => session.connectStopRequestToken, (token) => {
  if (token <= 0) {
    return
  }

  pendingNavigationOnConnect.value = false
  send({ type: 'bodymonitor_stdio_stop' })
})

watch(() => session.bodyMonitorState, (state) => {
  if (state === 'idle') {
    pendingNavigationOnConnect.value = false
  }
})

watch(
  () => {
    if (!reconnectModal.isOpen || reconnectModal.deviceMac === null) {
      return null
    }

    const targetDevice = topListDevices.value.find((d) => d.mac === reconnectModal.deviceMac)
    if (targetDevice === undefined) {
      return null
    }

    return getUnifiedDeviceStatus(targetDevice).cssClass
  },
  (cssClass) => {
    if (!reconnectModal.isOpen) {
      return
    }

    if (cssClass === 'device-list__status--online') {
      onReconnectModalDeviceConnected()
    }
  },
)

onMounted(() => {
  startPingPump()
})

onBeforeUnmount(() => {
  stopPingPump()
  stopReconnectPingLoop()
})
</script>

<style scoped>
.device-list {
  --device-list-control-width: clamp(12rem, 24vw, 16.25rem);
  --device-list-calibration-unit-width: 11.5rem;
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

.device-list__identity-title {
  align-items: center;
  flex: 0 1 auto;
  flex-wrap: wrap;
  gap: 8px;
  max-width: 100%;
  min-width: 0;
}

.device-list__identity-name {
  min-width: 0;
  overflow-wrap: anywhere;
}

.device-list__identity-capabilities {
  gap: 8px;
  min-width: 0;
}

.device-list__eeg-status-badge {
  flex: 0 0 auto;
}

.device-list__calibration-button--header {
  align-self: center;
  border-radius: 999px;
  min-height: auto;
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
  align-items: center;
  align-self: center;
  border: 1px solid rgba(148, 163, 184, 0.28);
  border-radius: 999px;
  display: inline-flex;
  gap: 6px;
  line-height: 1;
  padding: 4px 8px;
}

.device-list__status-icon {
  display: inline-flex;
  transform-origin: center;
}

.device-list__status-icon--spinning {
  animation: device-list-status-spin 1s linear infinite;
  will-change: transform;
}

@keyframes device-list-status-spin {
  from {
    transform: rotate(0deg);
  }

  to {
    transform: rotate(360deg);
  }
}

.device-list__status--inactive {
  background: rgba(234, 179, 8, 0.12);
  color: rgba(253, 224, 71, 0.95);
}

.device-list__status--online {
  background: rgba(34, 197, 94, 0.14);
  color: rgba(134, 239, 172, 0.95);
}

.device-list__status--searching {
  background: rgba(14, 165, 233, 0.16);
  color: rgba(125, 211, 252, 0.96);
}

.device-list__status--found {
  background: rgba(16, 185, 129, 0.16);
  color: rgba(167, 243, 208, 0.96);
}

.device-list__status--offline {
  background: rgba(100, 116, 139, 0.16);
  color: rgba(226, 232, 240, 0.92);
}

.device-list__remove-button {
  align-self: flex-start;
}

.device-list__collapse-button,
.device-list__calibration-button,
.device-list__toggle-button,
.device-list__add-button {
  align-self: flex-start;
}

.device-list__collapse-button {
  border-radius: 8px;
  box-shadow: inset 0 0 0 1px rgba(148, 163, 184, 0.16);
  transition:
    background-color 160ms ease,
    box-shadow 160ms ease,
    color 160ms ease;
}

.device-list__collapse-button--expanded {
  background: rgba(255, 255, 255, 0.06);
  box-shadow: inset 0 0 0 1px currentColor;
}

.device-list__collapse-button-content {
  gap: 1px;
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

.device-list__calibration-hub {
  align-items: flex-start;
  background:
    radial-gradient(circle at top left, rgba(37, 99, 235, 0.14), transparent 34%),
    rgba(15, 23, 42, 0.58);
  border: 1px solid rgba(96, 165, 250, 0.18);
  border-radius: 14px;
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  padding: 12px;
}

.device-list__calibration-cards {
  display: flex;
  flex: 1 1 auto;
  flex-wrap: wrap;
  gap: 10px;
  min-width: 0;
}

.device-list__calibration-card {
  background: rgba(2, 6, 23, 0.42);
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 12px;
  display: grid;
  align-content: start;
  flex: 0 0 var(--device-list-calibration-unit-width);
  gap: 10px;
  min-width: 0;
  padding: 10px 12px;
  width: var(--device-list-calibration-unit-width);
}

.device-list__calibration-card--attention {
  border-color: rgba(96, 165, 250, 0.26);
}

.device-list__calibration-card--relaxation {
  border-color: rgba(245, 158, 11, 0.24);
}

.device-list__calibration-card--drowse {
  border-color: rgba(148, 163, 184, 0.3);
}

.device-list__calibration-card--complete {
  border-color: rgba(34, 197, 94, 0.52);
  box-shadow: inset 0 0 0 1px rgba(74, 222, 128, 0.12);
}

.device-list__calibration-card--pending {
  border-color: rgba(245, 158, 11, 0.46);
  box-shadow: inset 0 0 0 1px rgba(251, 191, 36, 0.1);
}

.device-list__calibration-card-title {
  color: rgba(248, 250, 252, 0.96);
  font-size: 0.82rem;
  font-weight: 700;
  min-width: 0;
}

.device-list__calibration-card-date,
.device-list__calibration-card-time {
  color: rgba(148, 163, 184, 0.88);
  font-size: 0.74rem;
  line-height: 1.4;
}

.device-list__calibration-card-date {
  color: rgba(226, 232, 240, 0.94);
}

.device-list__calibration-card-reason {
  color: rgba(251, 191, 36, 0.96);
  font-size: 0.72rem;
  line-height: 1.35;
}

.device-list__calibration-card-badges {
  display: grid;
  gap: 8px;
}

.device-list__calibration-card-badge {
  background: rgba(15, 23, 42, 0.62);
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 999px;
  color: rgba(226, 232, 240, 0.96);
  font-size: 0.76rem;
  line-height: 1.35;
  padding: 6px 10px;
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

.device-list :deep(.q-btn.disabled),
.device-list :deep(.q-btn[disabled]) {
  background: rgba(100, 116, 139, 0.18) !important;
  border-color: rgba(148, 163, 184, 0.2) !important;
  box-shadow: none !important;
  color: rgba(226, 232, 240, 0.72) !important;
  opacity: 1 !important;
}

.device-list :deep(.q-btn.disabled .q-btn__content),
.device-list :deep(.q-btn[disabled] .q-btn__content) {
  color: inherit !important;
  opacity: 1 !important;
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

  .device-list__calibration-hub {
    flex-direction: column;
  }

  .device-list__calibration-card {
    flex-basis: 100%;
    width: 100%;
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

.device-list__reconnect-dialog {
  max-width: 400px;
  min-width: 280px;
}
</style>
