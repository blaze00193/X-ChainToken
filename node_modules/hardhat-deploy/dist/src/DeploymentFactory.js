"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    Object.defineProperty(o, k2, { enumerable: true, get: function() { return m[k]; } });
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DeploymentFactory = void 0;
const ethers_1 = require("ethers");
const zk = __importStar(require("zksync-web3"));
const address_1 = require("@ethersproject/address");
const solidity_1 = require("@ethersproject/solidity");
const bytes_1 = require("@ethersproject/bytes");
class DeploymentFactory {
    constructor(getArtifact, artifact, args, network, ethersSigner, overrides = {}) {
        this.overrides = overrides;
        this.getArtifact = getArtifact;
        this.isZkSync = network.zksync;
        this.artifact = artifact;
        if (this.isZkSync) {
            this.factory = new zk.ContractFactory(artifact.abi, artifact.bytecode, ethersSigner);
        }
        else {
            this.factory = new ethers_1.ContractFactory(artifact.abi, artifact.bytecode, ethersSigner);
        }
        const numArguments = this.factory.interface.deploy.inputs.length;
        if (args.length !== numArguments) {
            throw new Error(`expected ${numArguments} constructor arguments, got ${args.length}`);
        }
        this.args = args;
    }
    // TODO add ZkSyncArtifact
    async extractFactoryDeps(artifact) {
        // Load all the dependency bytecodes.
        // We transform it into an array of bytecodes.
        const factoryDeps = [];
        for (const dependencyHash in artifact.factoryDeps) {
            const dependencyContract = artifact.factoryDeps[dependencyHash];
            const dependencyBytecodeString = (await this.getArtifact(dependencyContract)).bytecode;
            factoryDeps.push(dependencyBytecodeString);
        }
        return factoryDeps;
    }
    async getDeployTransaction() {
        let overrides = this.overrides;
        if (this.isZkSync) {
            const factoryDeps = await this.extractFactoryDeps(this.artifact);
            const customData = {
                customData: {
                    factoryDeps,
                    feeToken: zk.utils.ETH_ADDRESS,
                },
            };
            overrides = Object.assign(Object.assign({}, overrides), customData);
        }
        return this.factory.getDeployTransaction(...this.args, overrides);
    }
    async calculateEvmCreate2Address(create2DeployerAddress, salt) {
        const deploymentTx = await this.getDeployTransaction();
        if (typeof deploymentTx.data !== 'string')
            throw Error('unsigned tx data as bytes not supported');
        return address_1.getAddress('0x' +
            solidity_1.keccak256(['bytes'], [
                `0xff${create2DeployerAddress.slice(2)}${salt.slice(2)}${solidity_1.keccak256(['bytes'], [deploymentTx.data]).slice(2)}`,
            ]).slice(-40));
    }
    async calculateZkCreate2Address(create2DeployerAddress, salt) {
        const bytecodeHash = zk.utils.hashBytecode(this.artifact.bytecode);
        const constructor = this.factory.interface.encodeDeploy(this.args);
        return zk.utils.create2Address(create2DeployerAddress, bytecodeHash, salt, constructor);
    }
    async getCreate2Address(create2DeployerAddress, create2Salt) {
        if (this.isZkSync)
            return await this.calculateZkCreate2Address(create2DeployerAddress, create2Salt);
        return await this.calculateEvmCreate2Address(create2DeployerAddress, create2Salt);
    }
    async compareDeploymentTransaction(transaction) {
        var _a;
        const newTransaction = await this.getDeployTransaction();
        const newData = (_a = newTransaction.data) === null || _a === void 0 ? void 0 : _a.toString();
        if (this.isZkSync) {
            const deserialize = zk.utils.parseTransaction(transaction.data);
            const desFlattened = bytes_1.hexConcat(deserialize.customData.factoryDeps);
            const factoryDeps = await this.extractFactoryDeps(this.artifact);
            const newFlattened = bytes_1.hexConcat(factoryDeps);
            return deserialize.data !== newData || desFlattened != newFlattened;
        }
        else {
            return transaction.data !== newData;
        }
    }
}
exports.DeploymentFactory = DeploymentFactory;
//# sourceMappingURL=DeploymentFactory.js.map