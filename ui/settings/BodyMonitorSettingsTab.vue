<template>
  <div class="bodymonitor-settings-tab">
    <div class="bodymonitor-settings-tab__content">
      <device-list />
    </div>
    <div class="bodymonitor-settings-tab__scan-block">
      <device-scan-block />
    </div>
  </div>
</template>

<script setup lang="ts">
import DeviceScanBlock from '../components/DeviceScanBlock.vue'
import DeviceList from '../components/DeviceList.vue'
</script>

<style scoped>
.bodymonitor-settings-tab {
  display: flex;
  flex-direction: column;
  gap: 16px;
  height: 100%;
  min-height: 0;
}

.bodymonitor-settings-tab__content {
  flex: 1 1 auto;
  min-height: 0;
  overflow: hidden;
}

.bodymonitor-settings-tab__scan-block {
  background: rgba(15, 23, 42, 0.55);
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 14px;
  padding: 14px;
}
</style>