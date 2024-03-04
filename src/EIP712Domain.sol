// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// solhint-disable func-name-mixedcase

/**
 * @title EIP712 Domain
 */
contract EIP712Domain {
    
    // was originally DOMAIN_SEPARATOR
    // but that has been moved to a method so we can override it in V2_2+
    bytes32 internal _DOMAIN_SEPARATOR;

    // to prevent signature replay attacks in the event the chain forks
    // fork chain would have different chain id to original chain
    uint256 internal immutable _DEPLOYMENT_CHAINID;

    /**
     * @notice Get the EIP712 Domain Separator.
     * @return The bytes32 EIP712 domain separator.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    /**
     * @dev Internal method to get the EIP712 Domain Separator.
     * @return The bytes32 EIP712 domain separator.
     */
    function _domainSeparator() internal virtual view returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

}
