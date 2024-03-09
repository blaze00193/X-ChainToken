# Deploy Params

## Set Gas limits

We use enforcedOptions to set gas limits of execution on dstChain.

> OptionsBuilder: https://remix.ethereum.org/#url=https://docs.layerzero.network/LayerZero/contracts/OptionsGenerator.sol&lang=en&optimize=false&runs=200&evmVersion=null&version=soljson-v0.8.24+commit.e11b9ed9.js

### Set gasLimits for lzReceive

To set gas limits for lzReceive, we need to utilise the lzReceive option:

> lzReceiveOption - handles setting gas and msg.value amounts when calling the destination contract's lzReceive method.

```solidity
    // hex"00030100110100000000000000000000000000030d40"
    Options.newOptions().addExecutorLzReceiveOption(200000, 0);

    // OR

    /// @notice Creates options for executing `lzReceive` on the destination chain.
    /// @param _gas The gas amount for the `lzReceive` execution.
    /// @param _value The msg.value for the `lzReceive` execution.
    /// @return bytes-encoded option set for `lzReceive` executor.
    function createLzReceiveOption(uint128 _gas, uint128 _value) public pure returns(bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, _value);
    }
```

The lzReceive option specifies the gas values the Executor uses when calling lzReceive on the destination chain.

- `_gas`: The amount of gas you'd provide for the lzReceive call in source chain native tokens. 200000 wei should be enough for most transactions.
- `_value`: The msg.value for the call. This value is often included to fund any operations that need native gas on the destination chain, including sending another nested message.

Thus, if we specify 200000 wei in gas, the executor will only execute as far as it can with that gas amount. Beyond that, it will revert. Naturally, the user is expected to pay of this gas on srcChain. Which is why when calling `quote`, sendParams in taken as an input, so that both extraOptions and enforcedOptions are accounted for in fees.
> The enforced options are concatenated with the extra options on the backend and calculated into the final quote

The bytestring produced is the `options` param in EnforcedOptionParam

```solidity

struct EnforcedOptionParam {
    uint32 eid; // Endpoint ID
    uint16 msgType; // Message Type
    bytes options; // Additional options
}

```

Hence in our deploy script when you see: `enforcedOptionParams[0] = EnforcedOptionParam(remoteChainID, 1, hex"00030100110100000000000000000000000000030d40");`, the executor only has 200000 wei of gas to operate with on the dstChain.
For the minting of an OFT token, we do not need `_value`, as there are no additional execution steps. We do need gas for the `lzReceive` execution (minting on dst), therefore `_gas`= 200000.

### Block msgType:2

We opt to block `sendAndCall` to prevent a potential attack vector that might block the messaging pathway and disable other incoming messages.

In LZv2, sendAndCall is denominated as msgType: 2. Thus to block it, we execute:

        // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
        enforcedOptionParams[1] = EnforcedOptionParam(homeChainID, 2, hex"000301001303000000000000000000000000000000000000");

This leaves the executor with 0 gas to operate with, and therefore the transaction reverts by default.

## Send Params

    /**
    * @dev Struct representing token parameters for the OFT send() operation.
    */
    struct SendParam {
        uint32 dstEid; // Destination endpoint ID.
        bytes32 to; // Recipient address.
        uint256 amountLD; // Amount to send in local decimals.
        uint256 minAmountLD; // Minimum amount to send in local decimals.
        bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
        bytes composeMsg; // The composed message for the send() operation.
        bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
    }


### Dropping gas on dstChain

Not all users will need this, thus we shall implement this via extraOptions, not enforcedOptions.
We will use `createLzNativeDropOption` to build this option, and pass the bytes as the extraOptions parameter in the SendParam struct.

See `SendTokensToRemotePlusGas` in Deploy script.

        // createLzNativeDropOption
        // gas: 6000000000000000 (amount of native gas to drop in wei)
        // receiver: 0x000000000000000000000000de05a1abb121113a33eed248bd91ddc254d5e9db (address in bytes32)
        bytes memory extraOptions = hex"0003010031020000000000000000001550f7dca70000000000000000000000000000de05a1abb121113a33eed248bd91ddc254d5e9db";

User will receive 0.006 ether of native gas tokens on the dstChain.