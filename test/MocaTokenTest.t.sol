// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import {MocaToken} from "./../src/token/MocaToken.sol";
import {MocaOFT} from "./../src/token/MocaOFT.sol";
import {MocaTokenAdaptor} from "./../src/token/MocaTokenAdaptor.sol";

abstract contract StateDeployed is Test {
    
    MocaToken public mocaToken;

    address public deployer;
    address public treasury;

    function setUp() public {

        //users
        deployer = makeAddr('deployer');
        treasury = makeAddr('treasury');

        vm.prank(deployer);

        // contracts
        string memory name = "TestToken"; 
        string memory symbol = "TT";
        
        mocaToken = new MocaToken(name, symbol, treasury);

    }
}


contract StateDeployedTest is StateDeployed {

    function testTotalSupply() public {
        
        // check minted supply
        assertEq(mocaToken.totalSupply(), 8_888_888_888 * 1e18);
        assertEq(mocaToken.balanceOf(treasury), 8_888_888_888 * 1e18);
        assertEq(mocaToken.balanceOf(deployer), 0);

    }
}
