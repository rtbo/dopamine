<script setup lang="ts">
import GithubLogo from '../assets/github-64.svg'
import { useOAuth } from '../model/oauth';

const oauth = useOAuth();

async function ghLogin() {
  const res = await oauth.authenticate("github");
  console.log(res);
}
</script>
<template>
  <div class="h-full w-full flex justify-center items-center">
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">Login</h2>
        <p>Login with one of the supported providers</p>
        <div class="card-actions space-x-4 justify-end">
          <button class="btn gap-2" @click="ghLogin()">
            <GithubLogo width="1.2em" height="1.2em" class="fill-current">
            </GithubLogo>
            Github
          </button>
          <button class="btn gap-2">
            <span class="iconify" data-icon="logos:google-icon"></span>
            Google
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
