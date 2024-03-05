# Setup

- forge install
- npm install

# Background

MocaToken is an omni-chain token, powered by LayerZero V2. It utilises the latest OFT standard and Endpoints as per the V2 iteration of the protocol.

MocaToken is not natively deployed through LayerZero, instead it is primarily deployed as a standalone ERC20 contract, following which integrated with LayerZero via the TokenAdaptor contract.
This token adaptor contract sits on the same chain as the deployed token contract (we refer to this as the home chain), and serves as a lockbox.

Essentially, users will have to lock their moca tokens on the home chain, by transferring it to the token adaptor contract, following which bridging can place. This is known as lock and mint.
> Please see: https://docs.layerzero.network/contracts/oft-adapter

On all other chains (remote chains), the MocaOFT contract is deployed. The OFT contract offers both ERC20 and LZ functionality.

Thus for a user to bridge when on the home chain, they would:

1. Grant approval for the Adaptor contract to spent the required amount of tokens
2. Call `send` on the Adaptor contract, supplying the input parameters specifying dstChain, amount to bridge, etc

![alt text](image-1.png)

In short, the core contracts are:

- MocaToken.sol 
- MocaTokenAdaptor.sol 
- MocaOFT.sol

The first two will be deployed on Ethereum, while the last one will be deployed on every other remote chain.

## Why do we opt to use the TokenAdaptor contract?

We felt that having the adaptor would be a useful security bulwark in case of an unexpected event, since it would be limited by approvals set and the liquidity at risk would be purely the tokens locked in it. 
In way, defence in depth.

## Gas-less transaction and Permit

1. EIP2621 is broken: https://www.trust-security.xyz/post/permission-denied
2. We want to still offer gasless transaction for our users.
3. Solution: EIP3009

EIP3009 has been successfully used by Circle, in its USDC implementation since v1. This offers us a degree of confidence.

To that end both MocaToken and MocaOFT contracts implemented the following functions:

- `transferWithAuthorization`
- `cancelAuthorization`
- `receiveWithAuthorization`

The primary difference between `transferWithAuthorization` and `receiveWithAuthorization` is that the latter function is called by the beneficiary of funds, providing a valid signature that was originally signed by the sender.
Both EOA and Smart contract signatures (EIP1271) are supported.

>Note that neither `increaseAllowance` nor `decreaseAllowance ` were implemented

## MocaToken Contract

- name = Moca
- symbol = MOCA
- dp = 18
- totalSupply = 8,888,888,888 ether

Total supply will be minted to the specified treasury address on deployment.

- Contract is neither upgradable nor is it pausable.
- Contract has no owner.
- It does not have a callable mint function.

It does have a standard `burn` function - msg.sender can burn his own assets. Nothing more.

## MocaTokenAdaptor Contract

Since we have opted to not natively deploy the token with LZ, the MocaTokenAdaptor contract will have to be deployed on the home chain alongside the MocaToken contract.

> See: https://docs.layerzero.network/contracts/oft-adapter

**For x-chain bridging, it is necessary to approve the OFT Adapter as a spender of your ERC20 token.**

## MocaOFT Contract

This contract will be deployed on all other remote chains, serving as a touchpoint for bridging. An execution example would be like so:

- Token is locked on home chain by MocaTokenAdaptor
- X-Chain message sent via LZ off-chain network
- MocaOFT contract on destination chain receives this message and mint the user address the appropriate amount of tokens.

Please see testnet deployments as a practical reference.

### Pausable

The contracts with LZ functionality, MocaOFT and MocaTokenAdaptor, implement Pausable.

While it is understood that the connectivity between two contracts can be severed via `setPeers`, we want to be anticipatory in dealing with unforeseeable circumstances. Especially so, given that the V2 iteration of LayerZero is fairly new, and any unexpected critical attacks would occur through the LZ vector, therefore also rendering the typical LZ safeguards non-operational.

Given its our first outing with LZ, best to be prepared.

## Testnet Deployments

V1: Deploy.s.sol

- MocaToken: https://sepolia.etherscan.io/address/0x9cb6dc4b71e285e26cbb0605f94b4031fe04c72c#readContract
- MocaTokenAdaptor: https://sepolia.etherscan.io/address/0x4114eccadf3b248da9eee7d8df2d3ba6bb02cbcd#readContract
- MocaOFT: https://mumbai.polygonscan.com/address/0x8bb305df680eda14e6b25b975bf1a8831acf69ab#events

V2: DeployMock.s.sol (has unrestricted mint function)

- MocaTokenMock: https://sepolia.etherscan.io/address/0xd70ee3ee58394d5dac6ccc05bb917081a5ce2ab1
- MocaTokenAdaptor: https://sepolia.etherscan.io/address/0xc8011cb9cfca55b822e56dd048dc960abd6424ce#code
- MocaOFT: https://mumbai.polygonscan.com/address/0x7d7b79b59ffb5c684a8bad8fb1729aaa27883dde

Please feel free to use V2 to make your own testnet transactions - the MocaToken contract in this deployment batch has an unrestricted public mint function.
V1 does not, and is meant to reflect how an actual deployment would be.

# Front-end Integration

## Crafting signatures

Looking at the test file MocaTokenTest.t.sol will give a clearer picture on the execution process, with respect to integration.

Note that DummyContractWallet.sol serves as an example of a smart contract wallet as part of testing support for EIP1271.
It's implementation of `isValidSignature` should be referenced.

If a smart contract wallet implements `isValidSignature` differently, the signature verification will fail.

## Crafting LZ params

Looking at Deploy.s.sol, contract `SendTokensToAway` will give you an idea what params need to be crafted before calling `mocaTokenAdaptor.send` to bridge.
Essentially its a 2-step process,

1. Call `mocaTokenAdaptor.quoteSend(sendParam, false)`
2. Call `mocaTokenAdaptor.send(.....)`

The first calls the layerZero endpoint contract on the same chain to get a gas cost quote for the specified bridging action. This value (or slightly more) must be passed as `msg.value` as part of the 2nd call.

As part of the deployment process I have enforced that users to pay a minimum of 200000 wei on the source chain. This is because a standard `lzReceive` call and token transfer on the destination chain should add up to be about that much on most EVM chains.

**For more details:**

- [OFT: Estimating-gas-fees](https://docs.layerzero.network/contracts/oft#estimating-gas-fees)
- [OFT: Calling-send](https://docs.layerzero.network/contracts/oft#calling-send)

- [Message Execution Options](https://docs.layerzero.network/contracts/options)
- [Estimating Gas Fees](https://docs.layerzero.network/contracts/estimating-gas-fees)
- [Transaction Pricing](https://docs.layerzero.network/contracts/transaction-pricing)

The DevTools repo is especially useful for reference examples:

- [devtools](https://github.com/LayerZero-Labs/devtools/?tab=readme-ov-file#bootstrapping-an-example-cross-chain-project)