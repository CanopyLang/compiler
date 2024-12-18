// eslint.config.js
import js from "@eslint/js";
import jsdoc from "eslint-plugin-jsdoc";

export default [
  // Base configuration for JavaScript
  js.configs.recommended,
  {
    files: ["**/*.js"], // Target all JavaScript files
    languageOptions: {
      ecmaVersion: 2021, // Enable ECMAScript 2021 syntax
      sourceType: "module", // Support ES modules (import/export)
    },
    plugins: {
      jsdoc, // Enable JSDoc plugin
    },
    rules: {
      ...js.configs.recommended.rules, // Include recommended ESLint rules

      // JavaScript rules
      "no-unused-vars": "warn", // Warn about unused variables
      eqeqeq: "error", // Require strict equality (=== and !==)
      curly: ["error", "all"], // Require curly braces for all control statements
      semi: ["error", "always"], // Enforce semicolons
      quotes: ["error", "double"], // Use single quotes for strings
      "no-console": "off", // Allow console statements

      // JSDoc rules
      "jsdoc/require-description": "error", // Enforce descriptions in JSDoc comments
      "jsdoc/check-values": "error", // Validate JSDoc tag values
    },
  },
];
