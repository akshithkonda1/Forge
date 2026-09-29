import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // eslint-plugin-react 7.37 still calls context.getFilename() when version is
  // "detect"; ESLint 10 removed that API. Pin the installed React version.
  {
    settings: {
      react: {
        version: "19.3.0",
      },
    },
  },
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
