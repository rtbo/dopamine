<script setup lang="ts">
import TheHeader from './components/TheHeader.vue'
</script>

<template>
  <div class="w-screen h-screen flex flex-col">
    <TheHeader></TheHeader>
    <div class="h-full w-full max-w-7xl mx-auto px-4 sm:px-6 md:px-8">
      <router-view></router-view>
    </div>
  </div>
</template>
