<template>
  <div class="field-help-text text-caption">{{ text }}</div>
</template>

<script setup lang="ts">
defineProps<{
  readonly text: string
}>()
</script>

<style scoped>
.field-help-text {
  color: rgba(203, 213, 225, 0.82);
  line-height: 1.45;
  min-width: 0;
  overflow-wrap: anywhere;
  white-space: pre-line;
}
</style>