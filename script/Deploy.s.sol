// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";

import {MocaToken} from "./../src/MocaToken.sol";
import {MocaOFT} from "./../src/MocaOFT.sol";
import {MocaTokenAdapter} from "./../src/MocaTokenAdapter.sol";

abstract contract LZState is Script {
    
    uint16 public ethereumID = 30101;
    address public ethereumEP = 0x1a44076050125825900e736c501f859c50fE728c;

    uint16 public polygonID = 30109;
    address public polygonEP = 0x1a44076050125825900e736c501f859c50fE728c;

    uint16 homeChainID = ethereumID;
    address homeLzEP = ethereumEP;

    uint16 remoteChainID = polygonID;
    address remoteLzEP = polygonEP;

    modifier broadcast() {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        _;

        vm.stopBroadcast();
    }
}


//Note: Deploy token + adaptor
contract DeployHome is LZState {
    
    // Note: update treasury, delegate addresses
    //      ownership will be handed over to multisig after deployment and config
    function run() public broadcast {

        // mint supply to treasury
        string memory name = "Moca"; 
        string memory symbol = "MOCA";
        address treasury = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        MocaToken mocaToken = new MocaToken(name, symbol, treasury);
        
        // set msg.sender as delegate and owner
        address deletate = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        address owner = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        MocaTokenAdapter mocaTokenAdapter = new MocaTokenAdapter(address(mocaToken), homeLzEP, deletate, owner);
    }
}


//Note: Deploy OFT on remote
contract DeployElsewhere is LZState {

    // Note: update delegate address
    //      ownership will be handed over to multisig after deployment and config
    function run() public broadcast {

        //params
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        address delegate = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;
        address owner = 0xdE05a1Abb121113a33eeD248BD91ddC254d5E9Db;

        MocaOFT remoteOFT = new MocaOFT(name, symbol, remoteLzEP, delegate, owner);
    }
}

//------------------------------ SETUP ------------------------------------

abstract contract State is LZState {
    
    // home
    address public mocaTokenAddress = address(0x0);    
    address public mocaTokenAdapterAddress = address(0x0);                     

    // remote
    address public mocaOFTAddress = address(0x0);

    // set contracts
    MocaToken public mocaToken = MocaToken(mocaTokenAddress);
    MocaTokenAdapter public mocaTokenAdapter = MocaTokenAdapter(mocaTokenAdapterAddress);

    MocaOFT public mocaOFT = MocaOFT(mocaOFTAddress);
}


// ------------------------------------------- Trusted Remotes: connect contracts -------------------------
contract SetRemoteOnHome is State {

    function run() public broadcast {
        // eid: The endpoint ID for the destination chain the other OFT contract lives on
        // peer: The destination OFT contract address in bytes32 format
        bytes32 peer = bytes32(uint256(uint160(address(mocaOFTAddress))));
        mocaTokenAdapter.setPeer(remoteChainID, peer);
    }
}

// 

contract SetRemoteOnAway is State {

    function run() public broadcast {
        // eid: The endpoint ID for the destination chain the other OFT contract lives on
        // peer: The destination OFT contract address in bytes32 format
        bytes32 peer = bytes32(uint256(uint160(address(mocaTokenAdapter))));
        mocaOFT.setPeer(homeChainID, peer);
        
    }
}

//

// ------------------------------------------- Gas Limits -------------------------

import { IOAppOptionsType3, EnforcedOptionParam } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract SetGasLimitsHome is State {

    function run() public broadcast {
        
        EnforcedOptionParam memory enforcedOptionParam;
        // msgType:1 -> a standard token transfer via send()
        // options: -> A typical lzReceive call will use 200000 gas on most EVM chains         
        EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](2);
        enforcedOptionParams[0] = EnforcedOptionParam(remoteChainID, 1, hex"00030100110100000000000000000000000000030d40");
        
        // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
        enforcedOptionParams[1] = EnforcedOptionParam(remoteChainID, 2, hex"000301001303000000000000000000000000000000000000");

        mocaTokenAdapter.setEnforcedOptions(enforcedOptionParams);
    }
}

// 


contract SetGasLimitsAway is State {

    function run() public broadcast {
        
        EnforcedOptionParam memory enforcedOptionParam;
        // msgType:1 -> a standard token transfer via send()
        // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
        EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](2);
        enforcedOptionParams[0] = EnforcedOptionParam(homeChainID, 1, hex"00030100110100000000000000000000000000030d40");
        
        // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
        enforcedOptionParams[1] = EnforcedOptionParam(homeChainID, 2, hex"000301001303000000000000000000000000000000000000");

        mocaOFT.setEnforcedOptions(enforcedOptionParams);
    }
}

//

// ------------------------------------------- Set Rate Limits  -----------------------------------------

contract SetRateLimitsHome is State {

    function run() public broadcast {
        
        mocaTokenAdapter.setOutboundLimit(remoteChainID, 10 ether);
        mocaTokenAdapter.setInboundLimit(remoteChainID, 10 ether);
    }
}

//

contract SetRateLimitsRemote is State {

    function run() public broadcast {

        mocaOFT.setOutboundLimit(homeChainID, 10 ether);
        mocaOFT.setInboundLimit(homeChainID, 10 ether);
    }
}

//


// ------------------------------------------- DVN Config  -----------------------------------------
import { SetConfigParam } from "node_modules/@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "node_modules/@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

abstract contract DvnData is State {
    
    address public layerZero_mainnet = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address public layerZero_polygon = 0x23DE2FE932d9043291f870324B74F820e11dc81A;
    
    // same address for both mainnet and polygon
    address public gcp = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;

    address public animoca_mainnet = 0x7E65BDd15C8Db8995F80aBf0D6593b57dc8BE437;
    address public animoca_polygon = 0xa6F5DDBF0Bd4D03334523465439D301080574742;
    
    address public nethermind_mainnet = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;
    address public nethermind_polygon = 0x31F748a368a893Bdb5aBB67ec95F232507601A73;

    // ...........................................................................

    // https://docs.layerzero.network/contracts/messagelib-addresses
    address public send302_mainnet = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address public receive302_mainnet = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
    
    address public send302_polygon = 0x6c26c61a97006888ea9E4FA36584c7df57Cd9dA3;
    address public receive302_polygon = 0x1322871e4ab09Bc7f5717189434f97bBD9546e95;   
}

contract SetDvnHome is DvnData {

    function run() public broadcast {

        // ulnConfig struct
        UlnConfig memory ulnConfig; 
            // confirmation on eth 
            ulnConfig.confirmations = 15;      
            
            // optional
            //0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
            ulnConfig.optionalDVNCount; 
            //no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
            ulnConfig.optionalDVNThreshold; 
            
            //required
            ulnConfig.requiredDVNCount = 4; 
            address[] memory requiredDVNs = new address[](ulnConfig.requiredDVNCount); 
                // no duplicates. sorted an an ascending order.
                requiredDVNs[0] = layerZero_mainnet;
                requiredDVNs[1] = animoca_mainnet;
                requiredDVNs[2] = nethermind_mainnet;
                requiredDVNs[3] = gcp;
                
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

        ILayerZeroEndpointV2(endPointAddress).setConfig(oappAddress, send302_mainnet, configParams);
        ILayerZeroEndpointV2(endPointAddress).setConfig(oappAddress, receive302_mainnet, configParams);
    }
}

//

//Note: Polygon
contract SetDvnRemote is DvnData {

    function run() public broadcast {

        // ulnConfig struct
        UlnConfig memory ulnConfig; 
            // confirmation on eth 
            ulnConfig.confirmations = 768;      
            
            // optional
            //0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
            ulnConfig.optionalDVNCount; 
            //no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
            ulnConfig.optionalDVNThreshold; 
            
            //required
            ulnConfig.requiredDVNCount = 4; 
            address[] memory requiredDVNs = new address[](ulnConfig.requiredDVNCount); 
                // no duplicates. sorted an an ascending order.
                requiredDVNs[0] = layerZero_polygon;
                requiredDVNs[1] = nethermind_polygon;
                requiredDVNs[2] = animoca_polygon;
                requiredDVNs[3] = gcp;
                
            ulnConfig.requiredDVNs = requiredDVNs;
        
        // config bytes
        bytes memory configBytes;
        configBytes = abi.encode(ulnConfig);

        // params
        SetConfigParam memory param1 = SetConfigParam({
            eid: homeChainID,     // dstEid
            configType: 2,
            config: configBytes
        });

        // array of params
        SetConfigParam[] memory configParams = new SetConfigParam[](1);
        configParams[0] = param1;
        
        //call endpoint
        address endPointAddress = remoteLzEP;
        address oappAddress = mocaOFTAddress;

        ILayerZeroEndpointV2(endPointAddress).setConfig(oappAddress, send302_polygon, configParams);
        ILayerZeroEndpointV2(endPointAddress).setConfig(oappAddress, receive302_polygon, configParams);
    }
}


// ------------------------------------------- Transfer Ownership to multisig -----------------------------------------

contract TransferOwnershipHome is DvnData {

    //Note: update multisig address
    function run() public broadcast {
        
        address multisig = address(0);
        mocaTokenAdapter.transferOwnership(multisig);
    }
}

// 

contract TransferOwnershipRemote is DvnData {

    //Note: update multisig address
    function run() public broadcast {
        
        address multisig = address(0);
        mocaOFT.transferOwnership(multisig);
    }
}