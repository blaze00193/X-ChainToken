import { TransactionRequest, TransactionResponse } from '@ethersproject/providers';
import { PayableOverrides, Signer } from 'ethers';
import { Artifact } from 'hardhat/types';
import * as zk from 'zksync-web3';
import { Address, ExtendedArtifact } from '../types';
export declare class DeploymentFactory {
    private factory;
    private artifact;
    private isZkSync;
    private getArtifact;
    private overrides;
    private args;
    constructor(getArtifact: (name: string) => Promise<Artifact>, artifact: Artifact | ExtendedArtifact, args: any[], network: any, ethersSigner?: Signer | zk.Signer, overrides?: PayableOverrides);
    private extractFactoryDeps;
    getDeployTransaction(): Promise<TransactionRequest>;
    private calculateEvmCreate2Address;
    private calculateZkCreate2Address;
    getCreate2Address(create2DeployerAddress: Address, create2Salt: string): Promise<Address>;
    compareDeploymentTransaction(transaction: TransactionResponse): Promise<boolean>;
}
//# sourceMappingURL=DeploymentFactory.d.ts.map