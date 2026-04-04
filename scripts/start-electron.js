const { spawn } = require("child_process");
const path = require("path");

const electronBinary = require("electron");
const projectRoot = path.resolve(__dirname, "..");

const env = { ...process.env };
delete env.ELECTRON_RUN_AS_NODE;

const child = spawn(electronBinary, ["."], {
  cwd: projectRoot,
  stdio: "inherit",
  env,
  shell: false
});

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }
  process.exit(code ?? 0);
});

child.on("error", (error) => {
  console.error("[start-electron] Failed to launch Electron:", error);
  process.exit(1);
});
