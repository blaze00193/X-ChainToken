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
        
        // Home: Mumbai
        if (block.chainid == homeChainId) { 

            // mint supply to treasury
            string memory name = "TestToken"; 
            string memory symbol = "TT";
            address treasury = msg.sender;
            MocaToken mocaToken = new MocaToken(name, symbol, treasury);
            
            // set msg.sender as delegate and owner
            address deletate = msg.sender;
            address owner = msg.sender;
            MocaTokenAdaptor mocaTokenAdaptor = new MocaTokenAdaptor(address(mocaToken), homeLzEP, deletate, owner);
        } 
        // Remote: 
        else if (block.chainid == remoteChainId) { 
            //params
            string memory name = "TestToken"; 
            string memory symbol = "TT";
            address delegate = msg.sender;
            address owner = msg.sender;

            MocaOFT remoteOFT = new MocaOFT(name, symbol, remoteLzEP, delegate, owner);
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
            enforcedOptionParam = EnforcedOptionParam({eid: remoteChainLZID, msgType: 1, options: "0x00030100110100000000000000000000000000030d40"});
        
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
            enforcedOptionParams[0] = enforcedOptionParam;

            mocaTokenAdaptor.setEnforcedOptions(enforcedOptionParams);

            // .............. Send some tokens
            
            //set approval for adaptor to spend tokens
            mocaToken.approve(mocaTokenAdaptorAddress, 1e18);

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
            remoteOFT.setPeer(homeChainLzID, peer);
                       
            //............ Set gasLimits on Remote

            EnforcedOptionParam memory enforcedOptionParam;
            // msgType:1 -> a standard token transfer via send()
            // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
            enforcedOptionParam = EnforcedOptionParam({eid: homeChainID, msgType: 1, options: "0x00030100110100000000000000000000000000030d40"});
            
            EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
            enforcedOptionParams[0] = enforcedOptionParam;

            remoteOFT.setEnforcedOptions(enforcedOptionParams);    
        }

    }
}


//Note: Deploy OFT on remote
contract DeployElsewhere is Script, LZState {

    function run() public sphinx {
        //params
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        address delegate = msg.sender;
        address owner = msg.sender;

        MocaOFT remoteOFT = new MocaOFT(name, symbol, remoteLzEP, delegate, owner);
    }
}

//forge script script/Deploy.s.sol:DeployElsewhere --rpc-url goerli --broadcast --verify -vvvv --etherscan-api-key goerli


//------------------------------ SETUP ------------------------------------

abstract contract State is LZState {

    address public mocaTokenAddress = address(0);    
    address public mocaTokenAdaptorAddress = address(0);                     

    // remote
    address public mocaOFTAddress = address(0);

    // set contracts
    MocaToken public mocaToken = MocaToken(mocaTokenAddress);
    MocaTokenAdaptor public mocaTokenAdaptor = MocaTokenAdaptor(mocaTokenAdaptorAddress);

    MocaOFT public mocaOFT = MocaOFT(mocaOFTAddress);

}


// ------------------------------------------- Trusted Remotes: connect contracts -------------------------
contract SetRemoteOnHome is State, Script {

    function run() public sphinx {
       
        // eid: The endpoint ID for the destination chain the other OFT contract lives on
        // peer: The destination OFT contract address in bytes32 format
        bytes32 peer = bytes32(uint256(uint160(address(mocaOFTAddress))));
        mocaTokenAdaptor.setPeer(remoteChainID, peer);
    }
}

// forge script script/Deploy.s.sol:SetRemoteOnHome --rpc-url sepolia --broadcast -vvvv

contract SetRemoteOnAway is State, Script {

    function run() public sphinx {

        // eid: The endpoint ID for the destination chain the other OFT contract lives on
        // peer: The destination OFT contract address in bytes32 format
        bytes32 peer = bytes32(uint256(uint160(address(mocaTokenAdaptor))));
        mocaOFT.setPeer(homeChainID, peer);

    }
}

// forge script script/Deploy.s.sol:SetRemoteOnAway --rpc-url goerli --broadcast -vvvv


// ------------------------------------------- Gas Limits -------------------------

import { IOAppOptionsType3, EnforcedOptionParam } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract SetGasLimitsHome is State, Script {

    function run() public sphinx {

        EnforcedOptionParam memory enforcedOptionParam;
        // msgType:1 -> a standard token transfer via send()
        // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
        enforcedOptionParam = EnforcedOptionParam({eid: remoteChainID, msgType: 1, options: "0x00030100110100000000000000000000000000030d40"});
    
        EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
        enforcedOptionParams[0] = enforcedOptionParam;

        mocaTokenAdaptor.setEnforcedOptions(enforcedOptionParams);

    }
}

// forge script script/Deploy.s.sol:SetGasLimitsHome --rpc-url sepolia --broadcast -vvvv


contract SetGasLimitsAway is State, Script {

    function run() public sphinx {
      
        EnforcedOptionParam memory enforcedOptionParam;
        // msgType:1 -> a standard token transfer via send()
        // options: -> A typical lzReceive call will use 200000 gas on most EVM chains 
        enforcedOptionParam = EnforcedOptionParam({eid: homeChainID, msgType: 1, options: "0x00030100110100000000000000000000000000030d40"});
        
        EnforcedOptionParam[] memory enforcedOptionParams = new EnforcedOptionParam[](1);
        enforcedOptionParams[0] = enforcedOptionParam;

        mocaOFT.setEnforcedOptions(enforcedOptionParams);

    }
}

// forge script script/Deploy.s.sol:SetGasLimitsAway --rpc-url goerli --broadcast -vvvv


// ------------------------------------------- Send sum tokens  -------------------------

// SendParam
import "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { MessagingParams, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract SendTokensToAway is State, Script {


    function run() public sphinx {
    
        //set approval for adaptor to spend tokens
        mocaToken.approve(mocaTokenAdaptorAddress, 1e18);
        
        SendParam memory sendParam = SendParam({
            dstEid: remoteChainID,
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
    }
}

//  forge script script/Deploy.s.sol:SendTokensToAway --rpc-url sepolia --broadcast -vvvv


/*
contract SendTokensToAwayAndCall is State, Script {

    struct LzCallParams {
        address payable refundAddress;
        address zroPaymentAddress;
        bytes adapterParams;
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TestToken testToken = TestToken(homeChainTokenContract);

        // defaultAdapterParams: min/max gas?
        bytes memory defaultAdapterParams = abi.encodePacked(uint16(1), uint256(200000));

        //payload and gas
        bytes memory _payload = abi.encodeWithSignature("setApprovalForAll(address,bool)", msg.sender, true);
        uint64 _dstGasForCall = 200000;

        // let nativeFee = (await localOFT.estimateSendFee(remoteChainId, bobAddressBytes32, initialAmount, false, defaultAdapterParams)).nativeFee
        (uint256 nativeFee, ) = testToken.estimateSendAndCallFee(goerliID, bytes32(uint256(uint160(0x2BF003ec9B7e2a5A8663d6B0475370738FA39825))), 1e18, _payload, _dstGasForCall, false, defaultAdapterParams);
        // sender sends tokens to himself on the remote chain
        
        // sender
        address _from = 0x2BF003ec9B7e2a5A8663d6B0475370738FA39825;
        // receiver
        uint16 _dstChainId = goerliID;
        bytes32 _toAddress = bytes32(uint256(uint160(0x2BF003ec9B7e2a5A8663d6B0475370738FA39825)));
        uint256 _amount = 1e18;
        
        ICommonOFT.LzCallParams memory _callParams;
        _callParams = ICommonOFT.LzCallParams({refundAddress: payable(0x2BF003ec9B7e2a5A8663d6B0475370738FA39825), zroPaymentAddress: address(0), adapterParams: defaultAdapterParams});

        //testToken.sendFrom{value: nativeFee}(_from, _dstChainId, _toAddress, _amount, _callParams);
        testToken.sendAndCall(_from, _dstChainId, _toAddress, _amount, _payload, _dstGasForCall, _callParams);

        vm.stopBroadcast();
    }
}

*/

//  forge script script/Deploy.s.sol:SendTokensToAwayAndCall --rpc-url sepolia --broadcast -vvvv