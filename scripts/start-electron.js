const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const electronBinary = require("electron");
const projectRoot = path.resolve(__dirname, "..");
const desktopFileName = "jac-browser.desktop";
const desktopSourcePath = path.join(projectRoot, desktopFileName);

const env = { ...process.env };
delete env.ELECTRON_RUN_AS_NODE;

if (process.platform === "linux") {
  const applicationsDir = path.join(os.homedir(), ".local", "share", "applications");
  const desktopTargetPath = path.join(applicationsDir, desktopFileName);

  try {
    fs.mkdirSync(applicationsDir, { recursive: true });
    if (fs.existsSync(desktopSourcePath)) {
      fs.copyFileSync(desktopSourcePath, desktopTargetPath);
    }
  } catch (error) {
    console.warn("[start-electron] Failed to sync desktop entry:", error.message);
  }

  env.CHROME_DESKTOP = desktopFileName;
}

const child = spawn(electronBinary, ["--class=Jac Browser", "."], {
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
