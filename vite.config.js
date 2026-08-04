import tailwindcss from "@tailwindcss/vite";
import { resolve } from "node:path";
import { defineConfig } from "vite";

export default defineConfig({
  base: process.env.GITHUB_ACTIONS ? "/AOI/" : "/",
  plugins: [tailwindcss()],
  build: {
    rollupOptions: {
      input: {
        index: resolve(import.meta.dirname, "index.html"),
        login: resolve(import.meta.dirname, "login.html"),
        workspace: resolve(import.meta.dirname, "workspace.html"),
        interns: resolve(import.meta.dirname, "interns.html"),
      },
    },
  },
});
