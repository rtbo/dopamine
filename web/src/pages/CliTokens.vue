<script setup lang="ts">
import { Icon } from "@iconify/vue"
import { computed, ref, watchEffect } from "vue";
import { host, getAuthCliTokens, delAuthCliTokens, postAuthCliTokens } from "../model/api";
import type { ElidedCliToken, CliToken } from "../model/api";
import { useAuthStore } from "../stores/auth";
import { useClipboard } from "@vueuse/core";

const store = useAuthStore();

const tokens = ref<ElidedCliToken[]>([]);

watchEffect(() => getAuthCliTokens(store.idToken).then((toks) => (tokens.value = toks)));

const createName = ref("");
const createHasExp = ref(true);
const createValidity = ref(30);
const showCreated = ref(false);
const created = ref<CliToken | null>(null);

const createdCommand = computed(() => `dop login --registry ${host} ${created.value?.token}`)

const { copy: commandCopy, copied } = useClipboard({ source: createdCommand });
const copyIcon = computed(() => copied.value ? "mdi:check" : "mdi-console");

async function create() {
  created.value = await postAuthCliTokens(
    store.idToken,
    createName.value,
    createHasExp.value ? createValidity.value : undefined
  );
  showCreated.value = true;
  getAuthCliTokens(store.idToken).then((toks) => (tokens.value = toks));
}

function doneShowCreated() {
  created.value = null;
  showCreated.value = false;
}

async function revoke(tok: ElidedCliToken) {
  console.log(tok);
  tokens.value = await delAuthCliTokens(store.idToken, tok.elidedToken);
}
</script>

<template>
  <div class="w-full max-w-lg">
    <h1 class="text-lg mb-2">CLI tokens</h1>
    <div class="card bg-base-200">
      <div class="card-body" v-if="!showCreated">
        <h2>Create new Token</h2>
        <div class="form-control">
          <input type="text" placeholder='Token name (e.g. "Linux laptop")'
            class="input max-w-xs" v-model="createName" />
          <label class="label">
            <input type="checkbox" v-model="createHasExp" class="checkbox" />
            <span class="label-text">valid for</span>
            <input type="number" class="input w-24" v-model="createValidity"
              :disabled="!createHasExp" />
            <span class="label-text">days</span>
          </label>
        </div>
        <div class="card-actions justify-end">
          <button class="btn btn-primary" @click="create">
            <span class="iconify" data:icon="mdi:plus"></span>
            Create
          </button>
        </div>
      </div>
      <div v-else class="card-body">
        <h2>New token created</h2>
        <p>
          Name: {{ created?.name ?? "(no name)" }}
        </p>
        <p>
          Expires: {{ created?.expJs ? (new
              Date(created.expJs)).toLocaleString() : "never"
          }}
        </p>
        <p>This token will be showed only once. Run the following command to use
          it locally:</p>
        <code class="bg-base-300">
          {{ createdCommand }}
        </code>
        <div class="card-actions justify-end">
          <button class="btn btn-ghost" @click="commandCopy()">
            <Icon :icon="copyIcon"></Icon>
            &nbsp;Copy
          </button>
          <button class="btn" @click="doneShowCreated">Done</button>
        </div>
      </div>
    </div>
    <div v-for="tok in tokens" :key="tok.elidedToken" class="card max-w-md">
      <div class="card-body">
        <h2 v-if="tok.name" class="card-title">{{ tok.name }}</h2>
        <p v-if="tok.expJs">Expires: {{ new Date(tok.expJs).toLocaleString() }}
        </p>
        <p>
          <code>{{ tok.elidedToken }}</code>
        </p>
        <div class="card-actions justify-end">
          <button @click="revoke(tok)">Revoke</button>
        </div>
      </div>
    </div>
  </div>
</template>
