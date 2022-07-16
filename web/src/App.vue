<script setup lang="ts">
import { useRoute, useRouter } from 'vue-router';
import TheHeader from './components/TheHeader.vue'
import { provideOAuth } from './model/oauth';
import { useAuthStore } from './stores/auth';

provideOAuth();

const authStore = useAuthStore();
const router = useRouter();
const route = useRoute();

authStore.initialize();

router.beforeEach((to) => {
  if (to.meta.requiresAuth) {
    if (!authStore.loggedIn) {
      return {
        path: "/login",
        query: { redirectTo: to.path },
      };
    }
  }
});

authStore.$subscribe(() => {
  if (route.meta.requiresAuth && !authStore.refreshToken) {
    router.push({
      path: "/login",
      query: { redirectTo: route.path }
    })
  }
})

</script>

<template>
  <div class="w-screen h-screen flex flex-col">
    <TheHeader></TheHeader>
    <div class="h-full w-full max-w-7xl mx-auto px-4 sm:px-6 md:px-8">
      <router-view></router-view>
    </div>
  </div>
</template>
