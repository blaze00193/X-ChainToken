# Background

1. EIP2621 is broken: https://www.trust-security.xyz/post/permission-denied
2. We want to still offer gasless transaction for our users.
3. Solution: EIP3009

EIP3009 has been successfully used by Circle, in its USDC implementation since v1. This offers us a degree of confidence.

EIP3009.sol and its dependencies were taken from the repo linked below.

- They were initially built with solidity version 0.6; we have updated them to 0.8.
- As part of the update, the only refactoring done was changing `now` to `block.timestamp`.
- Additionally, EIP3009.sol now inherits ERC20.sol (from OpenZeppelin V5).
- EIP3009.sol used to inherit AbstractFiatTokenV2 - it no longer does.
- Reference to AbstractFiatTokenV2 and AbstractFiatTokenV1 were dropped.

src: https://etherscan.deth.net/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48#code

## Setup

- forge install
- npm install

## MocaToken Contract

- name = Moca
- symbol = MOCA
- dp = 18
- totalSupply = 8,888,888,888 ether

Total supply will be minted to the specified treasury address on deployment.

- Contract is neither upgradable nor is pausable.
- Contract has no owner.
- It does not have a callable mint or burn function.

### Functions

Ignoring the standard ERC20 functions as per ERC20.sol, the following functions were added:

- `transferWithAuthorization`
- `cancelAuthorization`
- `receiveWithAuthorization`

These 3 functions are implemented in-line with EIP3009, serving as substitute for EIP2612.

The primary difference between `transferWithAuthorization` and `receiveWithAuthorization` is that the latter function is called by the beneficiary of funds, providing a valid signature that was originally signed by the sender.

Both EOA and Smart contract wallets signatures (EIP1271) are supported.

>Note that neither `increaseAllowance` nor `decreaseAllowance ` were implemented

## MocaTokenAdaptor Contract

Since we have opted to not natively deploy the token with LZ, the MocaTokenAdaptor contract will have to be deployed on the home chain alongside the MocaToken contract.

> See: https://docs.layerzero.network/contracts/oft-adapter

**For x-chain bridging, it is necessary to approve the OFT Adapter as a spender of your ERC20 token.**

## MocaOFT Contract

This contract will be deployed on all other remote chains, serving as a touchpoint for bridging. An execution example would be like so:

- Token is locked on home chain by MocaTokenAdaptor
- X-Chain message sent via LZ off-chain network
- MocaOFt contract on destination chain receives this message and mints the user address the appropriate amount of tokens.

Please see testnet deployments as a practical reference.

## Testnet Deployments

V1: Deploy.s.sol

- MocaToken: https://sepolia.etherscan.io/address/0x9cb6dc4b71e285e26cbb0605f94b4031fe04c72c#readContract
- MocaTokenAdaptor: https://sepolia.etherscan.io/address/0x4114eccadf3b248da9eee7d8df2d3ba6bb02cbcd#readContract
- MocaOFT: https://mumbai.polygonscan.com/address/0x8bb305df680eda14e6b25b975bf1a8831acf69ab#events

V2: DeployMock.s.sol (has unrestricted mint function)

- MocaTokenMock: https://sepolia.etherscan.io/address/0xd70ee3ee58394d5dac6ccc05bb917081a5ce2ab1
- MocaTokenAdaptor: https://sepolia.etherscan.io/address/0xc8011cb9cfca55b822e56dd048dc960abd6424ce#code
- MocaOFT: https://mumbai.polygonscan.com/address/0x7d7b79b59ffb5c684a8bad8fb1729aaa27883dde

For those that want to play out, use the set of contracts as part of the V2 deployment as MocaToken has an unrestricted public mint function.

V1 does not, and is meant to reflect how an actual deployment would be.

## Integration

### Crafting signatures

Looking at the test file MocaTokenTest.t.sol will give a clearer picture on the execution process, with respect to integration.

Note that DummyContractWallet.sol serves as an example of a smart contract wallet as part of testing support for EIP1271.
It's implementation of `isValidSignature` should be referenced.

If a smart contract wallet implements `isValidSignature` differently, the signature verification will fail.

### Crafting LZ params

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

# PENDING

- setEnforcedParams gasLimits on sendAndCall (msgType: 2)
- pausable modifier on send override

# Contingency (Proposed)

- off-chain monitoring of tokens bridged
- disconnect bridge when source chain emits malicious/incorrect LzSend event
-- what happens to the tokens on the src when you d/c the dst, after firing off on the src?

## Off-chain monitoring

Track I/O flows of tokens, ensuring that incorrect minting and burning does not occur.

When an incorrect lz event is emitted on the src chain, we look to disconnect the bridge by calling `setPeers` on the dst chain. Obviously, since the event is emitted on the src chain, nothing much can be done there. However, by breaking the connection between chains, on the dst chain we can essentially front-run the LZ relay and prevent a malicious mint.

![alt text](image.png)
**It is important to note that the end result of creating this blockage is that tokens will be lost on the src chain.**

In trying to prevent a malicious attack by breaking the bridge, it is also important to pause the contracts to prevent further txns from coming through on the src side.

Implementing this solution requires a db of all the addresses with MocaTokens across all chains. A script will conduct an accounting check, each time a `send` event is emitted, like so:

1. Verify that the user does indeed have the sufficient tokens on src chain for the bridging event.
2. Verify that the params passed in the event are accurate
3. Verify that the event emitted on dst and tokens minted are accurate.

Remediation:

- If step 2 fails, disconnect connection btw src and dst, on dst chain.
- If step 3 fails, pause bridging everywhere.

> Consider: https://forta.org/

## Alternative

A simple alternative is to just track global token balances on all chains, ensuring they add up to the correct total supply. The moment this value is breached, pause all bridging everywhere. 

### Remediation ?

Unknown. Successful resolution may not be possible, particularly in extreme circumstances.

In minor one-off instances, where the value lost through attack or bugged execution, the treasury could step-in and buy up that supply or cover user losses.