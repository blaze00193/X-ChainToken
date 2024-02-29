// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { EIP3009 } from "./EIP3009.sol";
import { EIP712 } from "./utils/EIP712.sol";

//Note: To be deployed everywhere else, outside of the home chain
//      18 dp
contract MocaOFT is OFT, EIP3009 {

    string internal constant _version = "v1";


    /**
     * @param _name token name
     * @param _symbol token symbol
     * @param _lzEndpoint LayerZero Endpoint address
     * @param _delegate The address capable of making OApp configurations inside of the endpoint.
     * @param _owner token owner
     */
    constructor(string memory _name, string memory _symbol, address _lzEndpoint, address _delegate, address _owner) 
        OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_owner) {

        _DEPRECATED_CACHED_DOMAIN_SEPARATOR = EIP712.makeDomainSeparator(_name, _version);
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function transferWithAuthorization(address from, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        _transferWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }

    /**
     * @notice Attempt to cancel an authorization
     * @dev Works only if the authorization is not yet used.
     * EOA wallet signatures should be packed in the order of r, s, v.
     * @param authorizer    Authorizer's address
     * @param nonce         Nonce of the authorization
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        _cancelAuthorization(authorizer, nonce, v, r, s);
    }

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev This has an additional check to ensure that the payee's address
     * matches the caller of this function to prevent front-running attacks.
     * EOA wallet signatures should be packed in the order of r, s, v.
     * @param from          Payer's address (Authorizer)
     * @param to            Payee's address
     * @param value         Amount to be transferred
     * @param validAfter    The time after which this is valid (unix time)
     * @param validBefore   The time before which this is valid (unix time)
     * @param nonce         Unique nonce
     * @param v             v of the signature
     * @param r             r of the signature
     * @param s             s of the signature
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {

        _receiveWithAuthorization(
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );
    }




}