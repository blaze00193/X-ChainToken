// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {MocaTokenMock} from "./../test/mocks/MocaTokenMock.sol";
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
        address treasury = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        MocaTokenMock mocaToken = new MocaTokenMock(name, symbol, treasury);
        
        // set msg.sender as delegate and owner
        address deletate = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        address owner = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        MocaTokenAdaptor mocaTokenAdaptor = new MocaTokenAdaptor(address(mocaToken), homeLzEP, deletate, owner);

        vm.stopBroadcast();
    }
}

// forge script script/DeployMock.s.sol:DeployHome --rpc-url sepolia --broadcast --verify -vvvv --etherscan-api-key sepolia
    

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

// forge script script/DeployMock.s.sol:DeployElsewhere --rpc-url polygon_mumbai --broadcast --verify -vvvv --etherscan-api-key polygon_mumbai


//------------------------------ SETUP ------------------------------------

abstract contract State is LZState {
    
    // home
    address public mocaTokenAddress = address(0xD70eE3ee58394D5daC6Ccc05Bb917081a5CE2ab1);    
    address public mocaTokenAdaptorAddress = address(0xC8011cB9cfCa55b822E56DD048dc960aBd6424Ce);                     

    // remote
    address public mocaOFTAddress = address(0x7d7b79b59Ffb5c684a8baD8fB1729AAA27883DDe);

    // set contracts
    MocaTokenMock public mocaToken = MocaTokenMock(mocaTokenAddress);
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

// forge script script/DeployMock.s.sol:SetRemoteOnHome --rpc-url sepolia --broadcast -vvvv

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

// forge script script/DeployMock.s.sol:SetRemoteOnAway --rpc-url polygon_mumbai --broadcast -vvvv


// ------------------------------------------- Gas Limits -------------------------

import { IOAppOptionsType3, EnforcedOptionParam } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract SetGasLimitsHome is State, Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EnforcedOptionParam memory enforcedOptionParam;
        // msgType:1 -> a standard token transfer via send()
        // options: -> A typical lzReceive call will use 200000 gas on most EVM chains         
        EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
        enforcedOptionParams[0] = EnforcedOptionParam(remoteChainID, 1, hex"00030100110100000000000000000000000000030d40");

        mocaTokenAdaptor.setEnforcedOptions(enforcedOptionParams);

        vm.stopBroadcast();
    }
}

// forge script script/DeployMock.s.sol:SetGasLimitsHome --rpc-url sepolia --broadcast -vvvv


contract SetGasLimitsAway is State, Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        EnforcedOptionParam memory enforcedOptionParam;
        // msgType:1 -> a standard token transfer via send()
        // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
        EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
        enforcedOptionParams[0] = EnforcedOptionParam(homeChainID, 1, hex"00030100110100000000000000000000000000030d40");

        mocaOFT.setEnforcedOptions(enforcedOptionParams);

        vm.stopBroadcast();
    }
}

// forge script script/DeployMock.s.sol:SetGasLimitsAway --rpc-url polygon_mumbai --broadcast -vvvv


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
            dstEid: remoteChainID,
            to: bytes32(uint256(uint160(address(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db)))),
            amountLD: 1 ether,
            minAmountLD: 1 ether,
            extraOptions: nullBytes,
            composeMsg: nullBytes,
            oftCmd: nullBytes
        });

        // Fetching the native fee for the token send operation
        MessagingFee memory messagingFee = mocaTokenAdaptor.quoteSend(sendParam, false);

        // send tokens xchain
        mocaTokenAdaptor.send{value: messagingFee.nativeFee}(sendParam, messagingFee, payable(0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db ));

        vm.stopBroadcast();
    }
}

//  forge script script/Deploy.s.sol:SendTokensToAway --rpc-url sepolia --broadcast -vvvv