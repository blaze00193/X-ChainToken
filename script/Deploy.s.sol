// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {MocaToken} from "./../src/MocaToken.sol";
import {MocaOFT} from "./../src/MocaOFT.sol";
import {MocaTokenAdaptor} from "./../src/MocaTokenAdaptor.sol";

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
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        address treasury = msg.sender;
        MocaToken mocaToken = new MocaToken(name, symbol, treasury);
        
        // set msg.sender as delegate and owner
        address deletate = msg.sender;
        address owner = msg.sender;
        MocaTokenAdaptor mocaTokenAdaptor = new MocaTokenAdaptor(address(mocaToken), homeLzEP, deletate, owner);

        vm.stopBroadcast();
    }
}


/**
    forge script script/Deploy.s.sol:DeployHome --rpc-url sepolia --broadcast --verify -vvvv --etherscan-api-key sepolia
    
    backup RPC:
    forge script script/Deploy.s.sol:DeployHome --rpc-url "https://rpc-mumbai.maticvigil.com" --broadcast --verify -vvvv --legacy --etherscan-api-key polygon
*/


//Note: Deploy OFT on remote
contract DeployElsewhere is Script, LZState {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //params
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        address delegate = msg.sender;
        address owner = msg.sender;

        MocaOFT remoteOFT = new MocaOFT(name, symbol, remoteLzEP, 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db, 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db);
        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:DeployElsewhere --rpc-url polygon_mumbai --broadcast --verify -vvvv --etherscan-api-key polygon_mumbai


//------------------------------ SETUP ------------------------------------

abstract contract State is LZState {
    
    // home
    address public mocaTokenAddress = address(0x9cb6dc4B71E285e26cbb0605F94B4031fE04C72c);    
    address public mocaTokenAdaptorAddress = address(0x4114eCCadF3b248DA9EEe7D8dF2d3bA6bB02Cbcd);                     

    // remote
    address public mocaOFTAddress = address(0x8BB305DF680edA14E6b25b975Bf1a8831AcF69ab);

    // set contracts
    MocaToken public mocaToken = MocaToken(mocaTokenAddress);
    MocaTokenAdaptor public mocaTokenAdaptor = MocaTokenAdaptor(mocaTokenAdaptorAddress);

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
        mocaTokenAdaptor.setPeer(remoteChainID, peer);
        
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
        bytes32 peer = bytes32(uint256(uint160(address(mocaTokenAdaptor))));
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
        
        // block sendAndCall: createLzReceiveOption() set gas requirement to be 1M
        enforcedOptionParams[1] = EnforcedOptionParam(homeChainID, 2, hex"000301001101000000000000000000000000000f4240");

        mocaTokenAdaptor.setEnforcedOptions(enforcedOptionParams);

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
        
        // block sendAndCall: createLzReceiveOption() set gas requirement to be 1M
        enforcedOptionParams[1] = EnforcedOptionParam(homeChainID, 2, hex"000301001101000000000000000000000000000f4240");

        mocaOFT.setEnforcedOptions(enforcedOptionParams);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetGasLimitsAway --rpc-url polygon_mumbai --broadcast -vvvv


// ------------------------------------------- Send sum tokens  -------------------------

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract SendTokensToAway is State, Script {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //set approval for adaptor to spend tokens
        mocaToken.approve(mocaTokenAdaptorAddress, 1e18);

        
        bytes memory nullBytes = new bytes(0);
        SendParam memory sendParam = SendParam({
            dstEid: remoteChainID,                                                               // Destination endpoint ID.
            to: bytes32(uint256(uint160(address(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db)))),  // Recipient address.
            amountLD: 1 ether,                                                                   // Amount to send in local decimals        
            minAmountLD: 1 ether,                                                                // Minimum amount to send in local decimals.
            extraOptions: nullBytes,                                                             // Additional options supplied by the caller to be used in the LayerZero message.
            composeMsg: nullBytes,                                                                // The composed message for the send() operation.
            oftCmd: nullBytes                                                                    // The OFT command to be executed, unused in default OFT implementations.
        });

        // Fetching the native fee for the token send operation
        MessagingFee memory messagingFee = mocaTokenAdaptor.quoteSend(sendParam, false);
        //MessagingFee memory messagingFee = mocaTokenAdaptor.quoteOFT(sendParam);

        // send tokens xchain
        mocaTokenAdaptor.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db));

        vm.stopBroadcast();
    }
}

//  forge script script/Deploy.s.sol:SendTokensToAway --rpc-url sepolia --broadcast -vvvv

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


contract SendAndCall is State, Script {
        
    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        //set approval for adaptor to spend tokens
        mocaToken.approve(mocaTokenAdaptorAddress, 1e18);

        
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
        MessagingFee memory messagingFee = mocaTokenAdaptor.quoteSend(sendParam, false);
        //MessagingFee memory messagingFee = mocaTokenAdaptor.quoteOFT(sendParam);

        // send tokens xchain
        mocaTokenAdaptor.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db));

        vm.stopBroadcast();
    }

}