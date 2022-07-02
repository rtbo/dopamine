<script setup lang="ts">
import { useRoute } from 'vue-router';
import { useAuthStore } from '../stores/auth';

const authStore = useAuthStore();
const route = useRoute();
</script>
<template>
  <header class="w-full mb-2 bg-base-200 border-b border-b-base-content/30">
    <nav class="max-w-7xl mx-auto navbar px-4 sm:px-6 md:px-8">
      <div class="flex-1">
        <span class="normal-case text-xl">Dopamine PM</span>
      </div>
      <div class="flex-none">
        <div v-if="authStore.loggedIn" class="dropdown dropdown-end">
          <label tabindex="0" class="btn btn-ghost btn-circle avatar">
            <div class="w-10 rounded-full">
              <img :src="authStore.avatarUrl" />
            </div>
          </label>
          <ul
            class="menu menu-compact dropdown-content mt-3 p-2 shadow bg-base-100 rounded-box w-52">
            <li>
              <button class="btn bg-base-200" @click="authStore.disconnect()">
                Logout
              </button>
            </li>
          </ul>
        </div>
        <router-link v-else
          :to="{ path: '/login', query: { redirectTo: route.path } }">
          Sign in
        </router-link>
      </div>
    </nav>
  </header>
</template>