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
        address owner = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
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
    address public mocaTokenAddress = address(0xFe149349285995D59Ec3FD6A5080840443906B45);    
    address public mocaTokenAdapterAddress = address(0xa8F355AE124d7120dAEA13239b6cC89FB0376779);                     

    // remote
    address public mocaOFTAddress = address(0x0EB26b982341c37A02812738C6c10EB0b66ef4F7);

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
import { MessagingParams, MessagingFee, MessagingReceipt, IMessageLibManager, ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

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
//   the user has "lost" a token. txn has to be retried on dst.


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
            composeMsg: "sendANdCALL",                                                           // The composed message for the send() operation.
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
import { SetConfigParam } from "node_modules/@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "node_modules/@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

abstract contract DvnData {
    
    address public layerZero_mainnet = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address public layerZero_polygon = 0x23DE2FE932d9043291f870324B74F820e11dc81A;
    
    // same address for both mainnet and polygon
    address public gcp = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;

    address public animoca_mainnet = 0x7E65BDd15C8Db8995F80aBf0D6593b57dc8BE437;
    address public animoca_polygon = 0xa6F5DDBF0Bd4D03334523465439D301080574742;
    
    address public nethermind_mainnet = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;
    address public nethermind_polygon = 0x31F748a368a893Bdb5aBB67ec95F232507601A73;

    //..............................................................................

    // testnet addressses 
    address public layerZero_testnet_sepolia = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193;
    address public layerZero_testnet_polygon = 0x67a822F55C5F6E439550b9C4EA39E406480a40f3;

    address public nethermind_testnet_ethereum = 0x715A4451Be19106BB7CefD81e507813E23C30768;
    address public nethermind_testnet_polygon = 0xC460CEcfcc7A69665cCd41Ebf25Dd2572c18f657;

    //..............................................................................

    // https://docs.layerzero.network/contracts/messagelib-addresses
    address public send302 = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;
    address public receive302 = 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851;
}

contract SetDvnHome is State, Script, DvnData {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // ulnConfig struct
        UlnConfig memory ulnConfig; 
            // confirmation on eth 
            ulnConfig.confirmations = 15;      
            
            ulnConfig.optionalDVNCount; 
            ulnConfig.optionalDVNThreshold; 
//            address[] memory optionalDVNs;

            ulnConfig.requiredDVNCount = 2; 
            address[] memory requiredDVNs = new address[](2); 
                requiredDVNs[0] = layerZero_testnet_polygon;
                requiredDVNs[1] = nethermind_testnet_ethereum;
            ulnConfig.requiredDVNs = requiredDVNs;
        
        // config bytes
        bytes memory configBytes;
        configBytes = abi.encode(ulnConfig);

        // params
        SetConfigParam memory param1 = SetConfigParam({
            eid: remoteChainID,     // dstEid
            configType: 2,
            config: configBytes
        });

        // array of params
        SetConfigParam[] memory configParams = new SetConfigParam[](1);
        configParams[0] = param1;
        
        //call endpoint
        address endPointAddress = homeLzEP;
        address oappAddress = mocaTokenAdapterAddress;

        ILayerZeroEndpointV2(endPointAddress).setConfig(oappAddress, send302, configParams);
        ILayerZeroEndpointV2(endPointAddress).setConfig(oappAddress, receive302, configParams);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetDvnHome --rpc-url sepolia --broadcast -vvvv
