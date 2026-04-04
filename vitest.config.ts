import { defineConfig } from "vitest/config";
import tsconfigPaths from "vite-tsconfig-paths";

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    environment: "node",
    // Resolve NodeNext-style .js imports to .ts source files
    resolveSnapshotPath(testPath, snapshotExtension) {
      return testPath + snapshotExtension;
    },
  },
  resolve: {
    extensions: [".ts", ".tsx", ".js"],
  },
});
