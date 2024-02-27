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

    uint16 homeChainLzID = mumbaiID;
    address homeLzEP = mumbaiEP;

    uint16 remoteChainLZID = arbSepoliaID;
    address remoteLzEP = arbSepoliaEP;

    uint256 homeChainId = 80001;     // mumbai
    uint256 remoteChainId = 421614;  // arb_sepolia


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

//Note: Deploy token + adaptor
contract Deploy is Script, LZState {
    
    function run() public sphinx {
        
        MocaToken mocaToken; 
        MocaTokenAdaptor mocaTokenAdaptor;
        MocaOFT mocaOFT;

        // Home: Mumbai
        if (block.chainid == homeChainId) { 

            // mint supply to treasury
            string memory name = "TestToken"; 
            string memory symbol = "TT";
            address treasury = msg.sender;
             mocaToken = new MocaToken(name, symbol, treasury);
            
            // set msg.sender as delegate and owner
            address deletate = msg.sender;
            address owner = msg.sender;
             mocaTokenAdaptor = new MocaTokenAdaptor(address(mocaToken), homeLzEP, deletate, owner);
        } 
        // Remote: 
        else if (block.chainid == remoteChainId) { 
            //params
            string memory name = "TestToken"; 
            string memory symbol = "TT";
            address delegate = msg.sender;
            address owner = msg.sender;

             mocaOFT = new MocaOFT(name, symbol, remoteLzEP, delegate, owner);
        }

        // setup params

        if (block.chainid == homeChainId) {

            //............ Set peer on Home
            bytes32 peer = bytes32(uint256(uint160(address(mocaOFT))));
            mocaTokenAdaptor.setPeer(remoteChainLZID, peer);

            //............ Set gasLimits on Home

            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
            enforcedOptionParam = EnforcedOptionParam({eid: remoteChainLZID, msgType: 1, options: 0x00030100110100000000000000000000000000030d40});
        
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
            enforcedOptionParams[0] = enforcedOptionParam;

            mocaTokenAdaptor.setEnforcedOptions(enforcedOptionParams);

            // .............. Send some tokens
            
            //set approval for adaptor to spend tokens
            mocaToken.approve(address(mocaTokenAdaptor), 1e18);

            // send params
            SendParam memory sendParam = SendParam({
                dstEid: remoteChainLZID,
                to: bytes32(uint256(uint160(address(msg.sender)))),
                amountLD: 1e18,
                minAmountLD: 1e18,
                extraOptions: '0x',
                composeMsg: '0x',
                oftCmd: '0x'
            });

            // Fetching the native fee for the token send operation
            MessagingFee memory messagingFee = mocaTokenAdaptor.quoteSend(sendParam, false);

            // send tokens xchain
            mocaTokenAdaptor.send(sendParam, messagingFee, payable(msg.sender));

        } else if (block.chainid == remoteChainId) {

            //............ Set peer on Remote

            bytes32 peer = bytes32(uint256(uint160(address(mocaTokenAdaptor))));
            mocaOFT.setPeer(homeChainLzID, peer);
                       
            //............ Set gasLimits on Remote

            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
            enforcedOptionParam = EnforcedOptionParam({eid: homeChainLzID, msgType: 1, options: "0x00030100110100000000000000000000000000030d40"});
            
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
            enforcedOptionParams[0] = enforcedOptionParam;

            mocaOFT.setEnforcedOptions(enforcedOptionParams);    
        }

    }
}