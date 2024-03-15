// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {MocaToken} from "./../src/MocaToken.sol";
import {MocaOFT} from "./../src/MocaOFT.sol";
import {MocaTokenAdapter} from "./../src/MocaTokenAdapter.sol";

abstract contract LZState {
    
    //Note: LZV2 testnet addresses

    uint16 public sepoliaID = 40161;
    address public sepoliaEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 public mumbaiID = 40109;
    address public mumbaiEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 public arbSepoliaID = 40231;
    address public arbSepoliaEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 homeChainID = sepoliaID;
    address homeLzEP = sepoliaEP;

    uint16 remoteChainID = mumbaiID;
    address remoteLzEP = mumbaiEP;
}

//Note: Deploy token + adaptor
contract DeployHome is Script, LZState {
    
    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // mint supply to treasury
        string memory name = "Moca"; 
        string memory symbol = "MOCA";
        address treasury = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        MocaToken mocaToken = new MocaToken(name, symbol, treasury);
        
        // set msg.sender as delegate and owner
        address deletate = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        address owner = 0x17bEA8F4ce3a933544b120b736A31a291482480c;
        MocaTokenAdapter mocaTokenAdapter = new MocaTokenAdapter(address(mocaToken), homeLzEP, deletate, owner);

        vm.stopBroadcast();
    }
}


// forge script script/Deploy.s.sol:DeployHome --rpc-url sepolia --broadcast --verify -vvvv --etherscan-api-key sepolia
    

//Note: Deploy OFT on remote
contract DeployElsewhere is Script, LZState {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //params
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        address delegate = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        address owner = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;

        MocaOFT remoteOFT = new MocaOFT(name, symbol, remoteLzEP, delegate, owner);
        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:DeployElsewhere --rpc-url polygon_mumbai --broadcast --verify -vvvv --etherscan-api-key polygon_mumbai


//------------------------------ SETUP ------------------------------------

abstract contract State is LZState {
    
    // home
    address public mocaTokenAddress = address(0xA2E400CE40C83270d8369eC971D0fc2e46D5056a);    
    address public mocaTokenAdapterAddress = address(0x5a9962874acA3b407aCeB14f64C7eF2C6255C880);                     

    // remote
    address public mocaOFTAddress = address(0xaa7A95e597a65EB06DaE4eD54f1b62e0535d9156);

    // set contracts
    MocaToken public mocaToken = MocaToken(mocaTokenAddress);
    MocaTokenAdapter public mocaTokenAdapter = MocaTokenAdapter(mocaTokenAdapterAddress);

    MocaOFT public mocaOFT = MocaOFT(mocaOFTAddress);
}


// ------------------------------------------- Trusted Remotes: connect contracts -------------------------
contract SetRemoteOnHome is State, Script {

    function run() public  {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
       
        // eid: The endpoint ID for the destination chain the other OFT contract lives on
        // peer: The destination OFT contract address in bytes32 format
        bytes32 peer = bytes32(uint256(uint160(address(mocaOFTAddress))));
        mocaTokenAdapter.setPeer(remoteChainID, peer);
        
        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetRemoteOnHome --rpc-url sepolia --broadcast -vvvv

contract SetRemoteOnAway is State, Script {

    function run() public {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // eid: The endpoint ID for the destination chain the other OFT contract lives on
        // peer: The destination OFT contract address in bytes32 format
        bytes32 peer = bytes32(uint256(uint160(address(mocaTokenAdapter))));
        mocaOFT.setPeer(homeChainID, peer);
        
        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetRemoteOnAway --rpc-url polygon_mumbai --broadcast -vvvv


// ------------------------------------------- Gas Limits -------------------------

import { IOAppOptionsType3, EnforcedOptionParam } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract SetGasLimitsHome is State, Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EnforcedOptionParam memory enforcedOptionParam;
        // msgType:1 -> a standard token transfer via send()
        // options: -> A typical lzReceive call will use 200000 gas on most EVM chains         
        EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](2);
        enforcedOptionParams[0] = EnforcedOptionParam(remoteChainID, 1, hex"00030100110100000000000000000000000000030d40");
        
        // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
        enforcedOptionParams[1] = EnforcedOptionParam(remoteChainID, 2, hex"000301001303000000000000000000000000000000000000");

        mocaTokenAdapter.setEnforcedOptions(enforcedOptionParams);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetGasLimitsHome --rpc-url sepolia --broadcast -vvvv


contract SetGasLimitsAway is State, Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        EnforcedOptionParam memory enforcedOptionParam;
        // msgType:1 -> a standard token transfer via send()
        // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
        EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](2);
        enforcedOptionParams[0] = EnforcedOptionParam(homeChainID, 1, hex"00030100110100000000000000000000000000030d40");
        
        // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
        enforcedOptionParams[1] = EnforcedOptionParam(homeChainID, 2, hex"000301001303000000000000000000000000000000000000");

        mocaOFT.setEnforcedOptions(enforcedOptionParams);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetGasLimitsAway --rpc-url polygon_mumbai --broadcast -vvvv

// ------------------------------------------- Set Rate Limits  -----------------------------------------

contract SetRateLimitsHome is State, Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        mocaTokenAdapter.setOutboundLimit(remoteChainID, 10 ether);
        mocaTokenAdapter.setInboundLimit(remoteChainID, 10 ether);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetRateLimitsHome --rpc-url sepolia --broadcast -vvvv

contract SetRateLimitsRemote is State, Script {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        mocaOFT.setOutboundLimit(homeChainID, 10 ether);
        mocaOFT.setInboundLimit(homeChainID, 10 ether);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetRateLimitsRemote --rpc-url polygon_mumbai --broadcast -vvvv

// ------------------------------------------- Send sum tokens  -----------------------------------------

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract SendTokensToAway is State, Script {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //set approval for adaptor to spend tokens
        mocaToken.approve(mocaTokenAdapterAddress, 1 ether);

        
        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteChainID,                                                               // Destination endpoint ID.
            to: bytes32(uint256(uint160(address(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db)))),  // Recipient address.
            amountLD: 1 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 1 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                               // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        // Fetching the native fee for the token send operation
        MessagingFee memory messagingFee = mocaTokenAdapter.quoteSend(sendParam, false);

        // send tokens xchain
        mocaTokenAdapter.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db));

        vm.stopBroadcast();
    }
}

//  forge script script/Deploy.s.sol:SendTokensToAway --rpc-url sepolia --broadcast -vvvv

contract SendTokensToHome is State, Script {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: homeChainID,                                                                 // Destination endpoint ID.
            to: bytes32(uint256(uint160(address(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db)))),  // Recipient address.
            amountLD: 1 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 1 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                               // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        // Fetching the native fee for the token send operation
        MessagingFee memory messagingFee = mocaOFT.quoteSend(sendParam, false);
        //MessagingFee memory messagingFee = mocaTokenAdapter.quoteOFT(sendParam);

        // send tokens xchain
        mocaOFT.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db));

        vm.stopBroadcast();
    }
}

//  forge script script/Deploy.s.sol:SendTokensToHome --rpc-url polygon_mumbai --broadcast -vvvv


contract SendTokensToRemotePlusGas is State, Script {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //set approval for adaptor to spend tokens
        mocaToken.approve(mocaTokenAdapterAddress, 1 ether);
        
        // createLzNativeDropOption
        // gas: 6000000000000000 (amount of native gas to drop in wei)
        // receiver: 0x000000000000000000000000de05a1abb121113a33eed248bd91ddc254d5e9db (address in bytes32)
        bytes memory extraOptions = hex"0003010031020000000000000000001550f7dca70000000000000000000000000000de05a1abb121113a33eed248bd91ddc254d5e9db";

        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteChainID,                                                                  // Destination endpoint ID.
            to: bytes32(uint256(uint160(address(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db)))),     // Recipient address.
            amountLD: 1 ether,                                                                      // Amount to send in local decimals        
            minAmountLD: 1 ether,                                                                   // Minimum amount to send in local decimals.
            extraOptions: extraOptions,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                               // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        // Fetching the native fee for the token send operation
        MessagingFee memory messagingFee = mocaTokenAdapter.quoteSend(sendParam, false);

        // send tokens xchain
        mocaTokenAdapter.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db));

        vm.stopBroadcast();
    }
}

//  forge script script/Deploy.s.sol:SendTokensToRemotePlusGas --rpc-url sepolia --broadcast -vvvv


// matic before: 1.35870840179732543 MATIC
// matic after: 1.36470840179732543 MATIC
// delta of 0.006 matic, as specified by gas dropped.


//Note: User bridges tokens.
//      Txn clears on src chain
//      Bridge is d/c on the dst chain, before message is received
//      what happens to the user token?    


//  starting balance: 8888888885000000000000000000
//  1. SendTokensToAway: send tokens on src
//  2. BreakBridge: break bridge on dst
//  Result:
//   tokens locked in adaptor on home chain
//   nothing minted on the dst. 
//   LZ relaying failed: https://testnet.layerzeroscan.com/tx/0xc76c780e0ab4a7ae4cbf1375d3795afbbf2cde09403c64174d1c32b011891420
//   the user has "lost" a token, as there is no way to retrieve it from the adaptor.

contract BreakBridge is State, Script {
    function run() public {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // eid:  The endpoint ID for the destination chain the other OFT contract lives on
        // peer: The destination OFT contract address in bytes32 format
        //        Set this to bytes32(0) to remove the peer address.
        mocaOFT.setPeer(homeChainID,  bytes32(0));
        
        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:BreakBridge --rpc-url polygon_mumbai --broadcast -vvvv


contract SendAndCallToRemote is State, Script {
        
    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //set approval for adaptor to spend tokens
        mocaToken.approve(mocaTokenAdapterAddress, 1e18);

        
        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteChainID,                                                               // Destination endpoint ID.
            to: bytes32(uint256(uint160(address(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db)))),  // Recipient address.
            amountLD: 1 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 1 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: "sendANdCALL",                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        // Fetching the native fee for the token send operation
        MessagingFee memory messagingFee = mocaTokenAdapter.quoteSend(sendParam, false);

        // send tokens xchain
       mocaTokenAdapter.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db));

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SendAndCallToRemote --rpc-url sepolia --broadcast -vvvv



// gas for sendPlusGas: 246,093  - 376,507
// gas for send: 241,340 - 369,942