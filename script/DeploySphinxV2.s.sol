// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Sphinx, Network} from "@sphinx-labs/contracts/SphinxPlugin.sol";

import {MocaToken} from "./../src/MocaToken.sol";
import {MocaOFT} from "./../src/MocaOFT.sol";
import {MocaTokenAdapter} from "./../src/MocaTokenAdapter.sol";

import { IOAppOptionsType3, EnforcedOptionParam } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import { SetConfigParam } from "node_modules/@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "node_modules/@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

abstract contract LZState is Sphinx, Script {
    
    uint16 public ethereumID = 30101;
    address public ethereumEP = 0x1a44076050125825900e736c501f859c50fE728c;

    uint16 public polygonID = 30109;
    address public polygonEP = 0x1a44076050125825900e736c501f859c50fE728c;

    uint16 homeChainID = ethereumID;
    address homeLzEP = ethereumEP;

    uint16 remoteChainID = polygonID;
    address remoteLzEP = polygonEP;

    // block.chainid
    uint256 public blockChainId_mumbai = 80001;
    uint256 public blockChainId_sepolia = 11155111;
    uint256 public blockChainId_arbSepolia = 421614;
    // live
    uint256 public blockChainId_mainnet = 1;
    uint256 public blockChainId_polygon = 137;

    //create2
    bytes32 public salt = bytes32("8");

    // token data
    string public name = "Moca";
    string public symbol = "MOCA";

    // priviledged addresses
    address public ownerMultiSig = 0x1291d48f9524cE496bE32D2DC33D5E157b6Ed1e3;
    address public treasuryMultiSig = 0xe35B78991633E8130131D6A73302F96678e80f8D;
}

abstract contract DvnData {
    
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

contract DeployFinal is LZState, DvnData {

    // Sphinx setup
    function configureSphinx() public override {
        sphinxConfig.owners = [address(0x5B7c596ef4804DC7802dB28618d353f7Bf14C619)]; // Add owner(s)
        sphinxConfig.orgId = "clu0e13bc0001t058dr9pubfl"; // Add Sphinx org ID
        
        sphinxConfig.testnets = ["arbitrum_sepolia", "polygon_mumbai"];
        sphinxConfig.mainnets = ["mainnet", "polygon"];

        sphinxConfig.projectName = "TestTokenV1";
        sphinxConfig.threshold = 1;

        sphinxConfig.saltNonce = 1;  //in the event of project clash
    }

    function precompileAddresses(address delegate, address owner) public returns(address, address, address) {

        // ------------- MOCA TOKEN ----------------------------------------------------------
        bytes memory mocaTokenParams = abi.encode(name, symbol, treasuryMultiSig);

        MocaToken mocaToken = MocaToken(vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(type(MocaToken).creationCode, mocaTokenParams)),
            deployer: CREATE2_FACTORY
        }));

        // ------------- MOCA TOKEN ADAPTOR ----------------------------------------------------
        address token = address(mocaToken);

        bytes memory mocaAdaptorParams = abi.encode(token, homeLzEP, delegate, owner);
        
        MocaTokenAdapter mocaTokenAdapter = MocaTokenAdapter(vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(type(MocaTokenAdapter).creationCode, mocaAdaptorParams)),
            deployer: CREATE2_FACTORY
        }));


        // ------------- MOCA TOKEN OFT: REMOTE --------------------------------------------------
        bytes memory mocaOFTparams = abi.encode(name, symbol, remoteLzEP, delegate, owner);
        
        MocaOFT mocaOFT = MocaOFT(vm.computeCreate2Address({
            salt: salt,
            initCodeHash: keccak256(abi.encodePacked(type(MocaOFT).creationCode, mocaOFTparams)),
            deployer: CREATE2_FACTORY
        }));

        return (address(mocaToken), address(mocaTokenAdapter), address(mocaOFT));
    }

    function run() public sphinx {
        
        // ownership will be handed over after config has been completed
        address owner = safeAddress();
        address delegate = safeAddress();

        (address mocaTokenAddress, address mocaTokenAdapterAddress, address mocaOFTAddress) = precompileAddresses(delegate, owner);
        
        // Home
        if (block.chainid == blockChainId_mainnet) {    

            // deploy token + adapter
            new MocaToken{ salt: salt }(name, symbol, treasuryMultiSig);
            new MocaTokenAdapter{ salt: salt }(address(mocaTokenAddress), homeLzEP, delegate, owner);
            
        // Remote  
        } else if (block.chainid == blockChainId_polygon) { 
            
            // deploy OFT
            new MocaOFT{ salt: salt }(name, symbol, remoteLzEP, delegate, owner);
        }


        // Home
        if (block.chainid == blockChainId_mainnet) { 
            
            MocaTokenAdapter mocaTokenAdapter = MocaTokenAdapter(mocaTokenAdapterAddress);
            
            //............ Set peer on Home
            bytes32 peer = bytes32(uint256(uint160(address(mocaOFTAddress))));
            mocaTokenAdapter.setPeer(remoteChainID, peer);


            //............ Set Gas Limits
            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains         
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](2);
            enforcedOptionParams[0] = EnforcedOptionParam(remoteChainID, 1, hex"00030100110100000000000000000000000000030d40");
            
            // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
            enforcedOptionParams[1] = EnforcedOptionParam(remoteChainID, 2, hex"000301001303000000000000000000000000000000000000");

            mocaTokenAdapter.setEnforcedOptions(enforcedOptionParams);


            //............ Set Rate Limits
            mocaTokenAdapter.setOutboundLimit(remoteChainID, 10 ether);
            mocaTokenAdapter.setInboundLimit(remoteChainID, 10 ether);
            
            //............ Config DVN
            setDvnHome(mocaTokenAdapterAddress);

            //...... delegate


            //............ TransferOwnership
            mocaTokenAdapter.transferOwnership(ownerMultiSig);

            

        // Remote
        } else if (block.chainid == blockChainId_polygon) { 

            MocaOFT mocaOFT = MocaOFT(mocaOFTAddress);

            //............ Set peer on Remote
            bytes32 peer = bytes32(uint256(uint160(address(mocaTokenAdapterAddress))));
            mocaOFT.setPeer(homeChainID, peer);


            //............ Set Gas Limits
            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](2);
            enforcedOptionParams[0] = EnforcedOptionParam(homeChainID, 1, hex"00030100110100000000000000000000000000030d40");
            
            // block sendAndCall: createLzReceiveOption() set gas:0 and value:0 and index:0
            enforcedOptionParams[1] = EnforcedOptionParam(homeChainID, 2, hex"000301001303000000000000000000000000000000000000");

            mocaOFT.setEnforcedOptions(enforcedOptionParams);


            //............ Set Rate Limits
            mocaOFT.setOutboundLimit(homeChainID, 10 ether);
            mocaOFT.setInboundLimit(homeChainID, 10 ether);

            //............ Config DVN
            setDvnRemote(mocaOFTAddress);

            //...... delegate

            //............ TransferOwnership
            mocaOFT.transferOwnership(ownerMultiSig);
        }
    }

    function setDvnHome(address mocaTokenAdapterAddress) public {
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

    function setDvnRemote(address mocaOFTAddress) public {
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


// npx sphinx propose script/DeployFinal.s.sol --networks mainnets
