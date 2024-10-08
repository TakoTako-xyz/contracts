const path = require("path");
const fs = require("fs");
const { task } = require("hardhat/config");
const { TASK_COMPILE } = require("hardhat/builtin-tasks/task-names");

require("@nomicfoundation/hardhat-toolbox");

task(
  TASK_COMPILE,
  "hook compile task to perform post-compile task",
  async (_, hre, runSuper) => {
    const { root } = hre.config.paths;
    const outputDir = path.resolve(root, "./abi");

    await runSuper();

    if (fs.existsSync(outputDir)) {
      fs.rmdirSync(outputDir, { recursive: true });
    }
    fs.mkdirSync(outputDir, { recursive: true });

    for (const artifactPath of await hre.artifacts.getArtifactPaths()) {
      const artifact = fs.readFileSync(artifactPath);
      const { abi, contractName } = JSON.parse(artifact.toString());
      if (!abi.length || contractName.includes("Mock")) continue;

      const target = path.join(outputDir, `${contractName}.json`);
      fs.copyFileSync(artifactPath, target);
    }
  }
);

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.7.6",
        settings: {
          optimizer: { enabled: true, runs: 200 },
          evmVersion: "istanbul",
        },
      },
    ],
  },
};
