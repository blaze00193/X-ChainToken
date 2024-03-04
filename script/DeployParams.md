# Deploy Params

## Set Gas limits

We use enforcedOptions to set gas limits.

### Set gasLimits for LzReceive

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

- `_gas`: The amount of gas you'd provide for the lzReceive call in source chain native tokens. 200000 should be enough for most transactions.
- `_value`: The msg.value for the call. This value is often included to fund any operations that need native gas on the destination chain, including sending another nested message.

The bytestring produced is the `options` param in EnforcedOptionParam

```solidity

struct EnforcedOptionParam {
    uint32 eid; // Endpoint ID
    uint16 msgType; // Message Type
    bytes options; // Additional options
}

```


Hence in our deploy script when you see: `enforcedOptionParams[0] = EnforcedOptionParam(remoteChainID, 1, hex"00030100110100000000000000000000000000030d40");`,
it means we are putting in place an enforced option (on the home chain), wrt to some remoteChain specified by the `eid`.

This means that when users wish to make a x-chain txn to the remoteChain, the Oapp will ensure these enforcedOptions are met; else the transaction fails and reverts.

For the minting of an OFT token, we do not need `_value`, as there are no additional execution steps. We do need gas for the `lzReceive` execution (minting on dst), therefore `_gas`= 200000.

### Block msgType:2

We opt to block `sendAndCall` to prevent a potential attack vector that might block the messsaging pathway and disable other incoming messages. 

In LZv2, sendAndCall is denominated as msgType: 2. Thus to block it, we execute:

        // block sendAndCall: createLzReceiveOption() set gas requirement to be 1M
        enforcedOptionParams[1] = EnforcedOptionParam(homeChainID, 2, hex"000301001101000000000000000000000000000f4240");

        mocaOFT.setEnforcedOptions(enforcedOptionParams);

We use the [OptionsBuilder](https://remix.ethereum.org/#url=https://docs.layerzero.network/LayerZero/contracts/OptionsGenerator.sol&lang=en&optimize=false&runs=200&evmVersion=null&version=soljson-v0.8.24+commit.e11b9ed9.js),  `createLzReceiveOption` function to compose the correct bytes-encoded option set for `lzReceive` executor.

We pass the following parameters into `createLzReceiveOption`:

- gas: 1000000 (amount consumed for x-chain call)
- value: 0     (amount of actual native currency you are sending across chains)

This gives us the output of `hex"00030100110100000000000000000000000000061a80"`. By setting required gas to be 1M, its a sensible block.

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

