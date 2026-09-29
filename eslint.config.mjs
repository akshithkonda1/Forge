import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Non-web trees and generated output in this repo:
    "node_modules/**",
    "coverage/**",
    "ForgeSwift/**",
    "ForgeWidget/**",
    "Forge.xcworkspace/**",
    "backend/**",
    "contracts/**",
    "scripts/**",
    "**/*.py",
    "**/*.swift",
  ]),
]);

export default eslintConfig;
