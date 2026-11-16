import { defineConfig } from "vite";

export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        main: "index.html",
        sprintDemo: "sprint-1-demo.html",
      },
    },
  },
});
