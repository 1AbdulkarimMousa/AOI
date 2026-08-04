const browserGlobals = {
  Blob: "readonly",
  URL: "readonly",
  URLSearchParams: "readonly",
  document: "readonly",
  location: "readonly",
  localStorage: "readonly",
  navigator: "readonly",
  setTimeout: "readonly",
  structuredClone: "readonly",
  window: "readonly",
};

export default [
  { ignores: ["dist/**", "node_modules/**"] },
  {
    files: ["src/**/*.js"],
    languageOptions: { ecmaVersion: "latest", sourceType: "module", globals: browserGlobals },
    rules: { "no-undef": "error", "no-unused-vars": ["error", { argsIgnorePattern: "^_" }] },
  },
  {
    files: ["tests/**/*.mjs", "vite.config.js"],
    languageOptions: { ecmaVersion: "latest", sourceType: "module" },
    rules: { "no-unused-vars": "error" },
  },
];
