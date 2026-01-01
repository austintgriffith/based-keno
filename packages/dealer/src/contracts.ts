import { readFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Path to foundry package (relative to dealer/src)
const FOUNDRY_PATH = join(__dirname, "..", "..", "foundry");

interface DeploymentMap {
  [address: string]: string;
}

interface ContractArtifact {
  abi: readonly object[];
  bytecode: { object: string };
  deployedBytecode: { object: string };
  methodIdentifiers: { [signature: string]: string };
}

interface LoadedContract {
  address: `0x${string}`;
  abi: readonly object[];
}

/**
 * Load deployment addresses from foundry's deployments directory
 */
function loadDeployments(chainId: number): DeploymentMap {
  const deploymentsPath = join(FOUNDRY_PATH, "deployments", `${chainId}.json`);

  if (!existsSync(deploymentsPath)) {
    throw new Error(
      `No deployments found for chain ${chainId}. Expected file at: ${deploymentsPath}`
    );
  }

  const content = readFileSync(deploymentsPath, "utf8");
  return JSON.parse(content);
}

/**
 * Load contract ABI from foundry's out directory
 */
function loadContractArtifact(contractName: string): ContractArtifact {
  const artifactPath = join(
    FOUNDRY_PATH,
    "out",
    `${contractName}.sol`,
    `${contractName}.json`
  );

  if (!existsSync(artifactPath)) {
    throw new Error(
      `Contract artifact not found for ${contractName}. Expected file at: ${artifactPath}`
    );
  }

  const content = readFileSync(artifactPath, "utf8");
  return JSON.parse(content);
}

/**
 * Find contract address by name in deployments
 */
function findContractAddress(
  deployments: DeploymentMap,
  contractName: string
): `0x${string}` {
  for (const [address, name] of Object.entries(deployments)) {
    if (name === contractName && address !== "networkName") {
      return address as `0x${string}`;
    }
  }
  throw new Error(`Contract ${contractName} not found in deployments`);
}

/**
 * Load a deployed contract's address and ABI
 */
export function loadContract(
  chainId: number,
  contractName: string
): LoadedContract {
  const deployments = loadDeployments(chainId);
  const address = findContractAddress(deployments, contractName);
  const artifact = loadContractArtifact(contractName);

  return {
    address,
    abi: artifact.abi,
  };
}

/**
 * Load all deployed contracts for a chain
 */
export function loadAllContracts(
  chainId: number
): Record<string, LoadedContract> {
  const deployments = loadDeployments(chainId);
  const contracts: Record<string, LoadedContract> = {};

  for (const [address, name] of Object.entries(deployments)) {
    if (name === "networkName" || typeof name !== "string") continue;

    try {
      const artifact = loadContractArtifact(name);
      contracts[name] = {
        address: address as `0x${string}`,
        abi: artifact.abi,
      };
    } catch (error) {
      console.warn(`Warning: Could not load artifact for ${name}`);
    }
  }

  return contracts;
}

/**
 * Check if deployments exist for a chain
 */
export function hasDeployments(chainId: number): boolean {
  const deploymentsPath = join(FOUNDRY_PATH, "deployments", `${chainId}.json`);
  return existsSync(deploymentsPath);
}
