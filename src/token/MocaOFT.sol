// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

//Note: To be deployed everywhere else, outside of the home chain
//      18 dp
contract MocaOFT is OFT {

    /**
     * @param _name token name
     * @param _symbol token symbol
     * @param _lzEndpoint LayerZero Endpoint address
     * @param _owner token owner
     */
    constructor(string memory _name, string memory _symbol, address _lzEndpoint,  address _owner) OFT(_name, _symbol, _lzEndpoint, _owner) Ownable(_owner) {
        

    }






}