// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Sphinx, Network} from "@sphinx-labs/contracts/SphinxPlugin.sol";

import {MocaToken} from "./../src/token/MocaToken.sol";
import {MocaOFT} from "./../src/token/MocaOFT.sol";
import {MocaTokenAdaptor} from "./../src/token/MocaTokenAdaptor.sol";

import { IOAppOptionsType3, EnforcedOptionParam } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

abstract contract LZState is Sphinx, Script {
    
    //Note: LZV2 testnet addresses

    uint16 public sepoliaID = 40161;
    address public sepoliaEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 public mumbaiID = 40109;
    address public mumbaiEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 public arbSepoliaID = 40231;
    address public arbSepoliaEP = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    uint16 homeChainID = mumbaiID;
    address homeLzEP = mumbaiEP;

    uint16 remoteChainID = arbSepoliaID;
    address remoteLzEP = arbSepoliaEP;

    // Sphinx setup
    function setUp() public {

        sphinxConfig.owners = [address(0x5B7c596ef4804DC7802dB28618d353f7Bf14C619)]; // Add owner(s)
        sphinxConfig.orgId = "clszio7580001djh8pvnrbaka"; // Add Sphinx org ID
        
        sphinxConfig.testnets = [
            Network.arbitrum_sepolia,
            Network.polygon_mumbai
        ];

        sphinxConfig.projectName = "TestTokenV2";
        sphinxConfig.threshold = 1;
    }


}

contract DeployV2 is LZState {
    function run() public sphinx {
        
        //Pre-compile the `CREATE2` addresses of contracts

        // ------------- MOCA TOKEN ----------------------------------------------------------
        string memory name = "TestToken";
        string memory symbol = "TTv2";
        address treasury = safeAddress();

        bytes memory mocaTokenParams = abi.encode(name, symbol, treasury);

        MocaToken mocaToken = MocaToken(vm.computeCreate2Address({
            salt: bytes32(0),
            initCodeHash: keccak256(abi.encodePacked(type(MocaToken).creationCode, mocaTokenParams)),
            deployer: CREATE2_FACTORY
        }));


        // ------------- MOCA TOKEN ADAPTOR ----------------------------------------------------
        address token = address(mocaToken);
        address layerZeroEndpoint = homeLzEP;
        address delegate = safeAddress();
        address owner = safeAddress();

        bytes memory mocaAdaptorParams = abi.encode(token, layerZeroEndpoint, delegate, owner);
        
        MocaTokenAdaptor mocaTokenAdaptor = MocaTokenAdaptor(vm.computeCreate2Address({
            salt: bytes32(0),
            initCodeHash: keccak256(abi.encodePacked(type(MocaTokenAdaptor).creationCode, mocaAdaptorParams)),
            deployer: CREATE2_FACTORY
        }));


        // ------------- MOCA TOKEN OFT: REMOTE --------------------------------------------------

        address layerZeroEndpointRemote = remoteLzEP;
        //address deletate = safeAddress();
        //address owner = safeAddress();

        bytes memory mocaOFTparams = abi.encode(name, symbol, layerZeroEndpointRemote, delegate, owner);
        
        MocaOFT mocaOFT = MocaOFT(vm.computeCreate2Address({
            salt: bytes32(0),
            initCodeHash: keccak256(abi.encodePacked(type(MocaOFT).creationCode, mocaOFTparams)),
            deployer: CREATE2_FACTORY
        }));



        // Deploy and initialize the contracts. ContractA exists on Poly_Mumbai (80001), and ContractB exists on Arb_Sepolia (421614)
        if (block.chainid == 80001) { // Home: Mumbai

            new MocaToken{ salt: bytes32(0) }(name, symbol, treasury);
            new MocaTokenAdaptor{ salt: bytes32(0) }(address(mocaToken), layerZeroEndpoint, delegate, owner);

        } else if (block.chainid == 421614) { // Remote
        
            new MocaOFT{ salt: bytes32(0) }(name, symbol, layerZeroEndpointRemote, delegate, owner);
        }

        // SETUP

        if (block.chainid == 80001) { // Home: Mumbai
        
            //............ Set peer on Home
            bytes32 peer = bytes32(uint256(uint160(address(mocaOFT))));
            mocaTokenAdaptor.setPeer(remoteChainID, peer);

            //............ Set gasLimits on Home

            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
            enforcedOptionParam = EnforcedOptionParam({eid: remoteChainID, msgType: 1, options: hex"00030100110100000000000000000000000000030d40"});
        
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
            enforcedOptionParams[0] = EnforcedOptionParam(remoteChainID, 1, hex"00030100110100000000000000000000000000030d40");

            mocaTokenAdaptor.setEnforcedOptions(enforcedOptionParams);

            // .............. Send some tokens
            
            //set approval for adaptor to spend tokens
            mocaToken.approve(address(mocaTokenAdaptor), 10 ether);
            mocaToken.mint(10 ether);

            // send params
            bytes memory nullBytes = new bytes(0);
            SendParam memory sendParam = SendParam({
                dstEid: remoteChainID,
                to: bytes32(uint256(uint160(address(msg.sender)))),
                amountLD: 1 ether,
                minAmountLD: 1 ether,
                extraOptions: nullBytes,
                composeMsg: nullBytes,
                oftCmd: nullBytes
            });

            // Fetching the native fee for the token send operation
            MessagingFee memory messagingFee = mocaTokenAdaptor.quoteSend(sendParam, false);

            // send tokens xchain
            mocaTokenAdaptor.send{value: messagingFee.nativeFee }(sendParam, messagingFee, payable(msg.sender));


        } else if (block.chainid == 421614) { // Remote

            //............ Set peer on Remote

            bytes32 peer = bytes32(uint256(uint160(address(mocaTokenAdaptor))));
            mocaOFT.setPeer(homeChainID, peer);
            

            //............ Set gasLimits on Remote

            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
            enforcedOptionParam = EnforcedOptionParam({eid: homeChainID, msgType: 1, options: "0x00030100110100000000000000000000000000030d40"});
            
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);

            enforcedOptionParams[0] = EnforcedOptionParam(homeChainID, 1, hex"00030100110100000000000000000000000000030d40");

            mocaOFT.setEnforcedOptions(enforcedOptionParams);      

        }

    }
}

// npx sphinx propose script/DeploySphinxV2.s.sol --networks testnets --tc DeployV2