// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Sphinx, Network} from "@sphinx-labs/contracts/SphinxPlugin.sol";

import {MocaToken} from "./../src/token/MocaToken.sol";
import {MocaOFT} from "./../src/token/MocaOFT.sol";
import {MocaTokenAdaptor} from "./../src/token/MocaTokenAdaptor.sol";

abstract contract LZState is Sphinx {
    
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

    function run() public sphinx {
        
        //Pre-compile the `CREATE2` addresses of contracts
        bytes memory creationCode = type(MocaToken).creationCode;
        bytes memory params = abi.encode("TestToken", "TT", 0x5B7c596ef4804DC7802dB28618d353f7Bf14C619);
        bytes memory initCode = abi.encodePacked(creationCode, params);

        MocaToken mocaToken = vm.computeCreate2Address({
            salt: bytes32(0),
            initCodeHash: initCode,
            deployer: CREATE2_FACTORY
        });


        // set msg.sender as delegate and owner
        address token = address(mocaToken);
        
        address deletate = msg.sender;
        address owner = msg.sender;
        bytes memory params = abi.encode("TestToken", "TT", 0x5B7c596ef4804DC7802dB28618d353f7Bf14C619);


        MocaTokenAdaptor mocaTokenAdaptor = MocaTokenAdaptor({
            salt: bytes32(0),
            initCodeHash: 
        });
    }

}

// npx sphinx propose script/DeploySphinxV2.s.sol --networks testnets --tc <>