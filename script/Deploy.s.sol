// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {MocaToken} from "./../src/token/MocaToken.sol";
import {MocaOFT} from "./../src/token/MocaOFT.sol";
import {MocaTokenAdaptor} from "./../src/token/MocaTokenAdaptor.sol";

abstract contract LZState {
    
    //Note: LZV2 testnet addresses

    uint16 public sepoliaID = 40161;
    address public sepoliaEP = 0x6edce65403992e310a62460808c4b910d972f10f;

    uint16 public mumbaiID = 40109;
    address public mumbaiEP = 0x6edce65403992e310a62460808c4b910d972f10f;

    uint16 public arbSepoliaID = 40231;
    address public arbSepoliaEP = 0x6edce65403992e310a62460808c4b910d972f10f;
}

//Note: Sepolia
contract DeployHome is Script, LZState {
    
    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TestToken testToken = new TestToken("TestToken", "TT", 8, sepoliaEP);
        vm.stopBroadcast();
    }
}


/**
    forge script script/Deploy.s.sol:DeployHome --rpc-url sepolia --broadcast --verify -vvvv --etherscan-api-key sepolia
    
    backup RPC:
    forge script script/Deploy.s.sol:DeployHome --rpc-url "https://rpc-mumbai.maticvigil.com" --broadcast --verify -vvvv --legacy --etherscan-api-key polygon
*/


//Note: goerli
contract DeployElsewhere is Script, LZState {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TestTokenElsewhere testToken = new TestTokenElsewhere("TestToken", "TT", 8, goerliEP);
        vm.stopBroadcast();
    }
}

//forge script script/Deploy.s.sol:DeployElsewhere --rpc-url goerli --broadcast --verify -vvvv --etherscan-api-key goerli


//------------------------------ SETUP ------------------------------------

abstract contract State is LZState {

    address payable public homeChainTokenContract = payable(0x0959c593bB41A340Dcd9CA6c090c2F919000B28d);    //sepolia
    address public awayChainTokenContract = 0x0ADAFB8574b3a59cF3176e1bD278C951c445D94d;                     //goerli

    uint16 public homeChainId = sepoliaID;    //sepolia
    uint16 public awayChainId = goerliID;    //goerli
}


// ------------------------------------------- Trusted Remotes: connect contracts -------------------------
contract SetRemoteOnHome is State, Script {

    function run() public  {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TestToken testToken = TestToken(homeChainTokenContract);

        // bytes path: concats the remote and the local contract address using abi.encodePacked(): [REMOTE_ADDRESS, LOCAL_ADDRESS]
        uint16 _remoteChainId = awayChainId;
        address remote = awayChainTokenContract;
        address local = homeChainTokenContract;
        bytes memory path = abi.encodePacked(remote, local);
        
        testToken.setTrustedRemote(_remoteChainId, path); 

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetRemoteOnHome --rpc-url sepolia --broadcast -vvvv

contract SetRemoteOnAway is State, Script {

    function run() public {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TestTokenElsewhere testToken = TestTokenElsewhere(awayChainTokenContract);

        // path: concats the remote and the local contract address using abi.encodePacked()
        uint16 _remoteChainId = homeChainId;
        address remote = homeChainTokenContract;
        address local = awayChainTokenContract;
        bytes memory _path = abi.encodePacked(remote, local);
        
        testToken.setTrustedRemote(_remoteChainId, _path); 

        vm.stopBroadcast();
    }

}

// forge script script/Deploy.s.sol:SetRemoteOnAway --rpc-url goerli --broadcast -vvvv


// ------------------------------------------- Gas Limits -------------------------
contract SetGasLimitsHome is State, Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TestToken testToken = TestToken(homeChainTokenContract);

        //uint16 _dstChainId,
        //uint16 _packetType,
        //uint _minGas
        testToken.setMinDstGas(awayChainId, 0, 200000);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetGasLimitsHome --rpc-url sepolia --broadcast -vvvv


contract SetGasLimitsAway is State, Script {

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // token on mumbai
        TestTokenElsewhere testToken = TestTokenElsewhere(awayChainTokenContract);

        //uint16 _dstChainId,
        //uint16 _packetType,
        //uint _minGas
        testToken.setMinDstGas(homeChainId, 0, 200000);

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:SetGasLimitsAway --rpc-url goerli --broadcast -vvvv


// ------------------------------------------- Send sum tokens  -------------------------

import "lib/solidity-examples/contracts/token/oft/v2/interfaces/ICommonOFT.sol";

// sepolia -> goerli
contract SendTokensToAway is State, Script {

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

        // let nativeFee = (await localOFT.estimateSendFee(remoteChainId, bobAddressBytes32, initialAmount, false, defaultAdapterParams)).nativeFee
        (uint256 nativeFee, ) = testToken.estimateSendFee(goerliID, bytes32(uint256(uint160(0x2BF003ec9B7e2a5A8663d6B0475370738FA39825))), 1e18, false, defaultAdapterParams);

        /**
        * @dev send `_amount` amount of token to (`_dstChainId`, `_toAddress`) from `_from`
        * `_from` the owner of token
        * `_dstChainId` the destination chain identifier
        * `_toAddress` can be any size depending on the `dstChainId`.
        * `_amount` the quantity of tokens in wei
        * `_refundAddress` the address LayerZero refunds if too much message fee is sent
        * `_zroPaymentAddress` set to address(0x0) if not paying in ZRO (LayerZero Token)
        * `_adapterParams` is a flexible bytes array to indicate messaging adapter services
        */ 

        // sender sends tokens to himself on the remote chain
        
        // sender
        address _from = 0x2BF003ec9B7e2a5A8663d6B0475370738FA39825;
        // receiver
        uint16 _dstChainId = goerliID;
        bytes32 _toAddress = bytes32(uint256(uint160(0x2BF003ec9B7e2a5A8663d6B0475370738FA39825)));
        uint256 _amount = 1e18;
        
        ICommonOFT.LzCallParams memory _callParams;
        _callParams = ICommonOFT.LzCallParams({refundAddress: payable(0x2BF003ec9B7e2a5A8663d6B0475370738FA39825), zroPaymentAddress: address(0), adapterParams: defaultAdapterParams});

        testToken.sendFrom{value: nativeFee}(_from, _dstChainId, _toAddress, _amount, _callParams);

        vm.stopBroadcast();
    }

}

//  forge script script/Deploy.s.sol:SendTokensToAway --rpc-url sepolia --broadcast -vvvv

// mint + allowance on endpoint.
// msg.sender:  0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38  -> foundry bug?

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



//  forge script script/Deploy.s.sol:SendTokensToAwayAndCall --rpc-url sepolia --broadcast -vvvv