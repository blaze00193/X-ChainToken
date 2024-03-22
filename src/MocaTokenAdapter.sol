// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { OFTAdapter } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

// LZ Structs
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { SendParam, MessagingFee, MessagingReceipt, OFTReceipt } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";


//Note: Adapter is only to be deployed on the home chain where the token contract was originally deployed. 
//      Must approve OFT Adapter as a spender of your ERC20 token.
contract MocaTokenAdapter is OFTAdapter, Ownable2Step {

    // Outbound limits
    mapping(uint32 eid => uint256 outboundLimit) public outboundLimits;
    mapping(uint32 eid => uint256 sentTokenAmount) public sentTokenAmounts;
    mapping(uint32 eid => uint256 lastSentTimestamp) public lastSentTimestamps;

    // Inbound limits
    mapping(uint32 eid => uint256 inboundLimit) public inboundLimits;
    mapping(uint32 eid => uint256 receivedTokenAmount) public receivedTokenAmounts;
    mapping(uint32 eid => uint256 lastReceivedTimestamp) public lastReceivedTimestamps;

    // If an address is whitelisted, limit checks are skipped
    mapping(address addr => bool isWhitelisted) public whitelist;

    // if an address is an operator is can disconnect/connect bridges via setPeers
    mapping(address addr => bool isOperator) public operators;

    // events 
    event SetOutboundLimit(uint32 indexed eid, uint256 limit);
    event SetInboundLimit(uint32 indexed eid, uint256 limit);
    event SetWhitelist(address indexed addr, bool isWhitelist);
    event SetOperator(address indexed addr, bool isWhitelist);

    // errors
    error ExceedInboundLimit(uint256 limit, uint256 amount);
    error ExceedOutboundLimit(uint256 limit, uint256 amount);

    /**
     * @param token a deployed, already existing ERC20 token address
     * @param layerZeroEndpoint local endpoint address
     * @param delegate The address capable of making OApp configurations inside of the endpoint.
     * @param owner token owner
     */
    constructor(address token, address layerZeroEndpoint, address delegate, address owner) 
        OFTAdapter(token, layerZeroEndpoint, delegate) Ownable(owner) {
    }

    /*//////////////////////////////////////////////////////////////
                              RATE LIMITS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Owner to set the max daily limit on onbound x-chain transfers
     * @param eid Destination eid, as per LayerZero
     * @param limit Daily outbound limit
     */
    function setOutboundLimit(uint32 eid, uint256 limit) external onlyOwner {
        outboundLimits[eid] = limit;
        emit SetOutboundLimit(eid, limit);
    }

    /**
     * @dev Owner to set the max daily limit on inbound x-chain transfers
     * @param eid Destination eid, as per LayerZero
     * @param limit Daily inbound limit
     */
    function setInboundLimit(uint32 eid, uint256 limit) external onlyOwner {
        inboundLimits[eid] = limit;
        emit SetInboundLimit(eid, limit);
    }

    /**
     * @dev Owner to set whitelisted addresses - limits do not apply to these addresses 
     * @param addr address
     * @param isWhitelisted true/false
     */
    function setWhitelist(address addr, bool isWhitelisted) external onlyOwner {
        whitelist[addr] = isWhitelisted;
        emit SetWhitelist(addr, isWhitelisted);
    }

    /**
     * @dev Owner to set operator addresses - these addresses can call setPeers
     * @param addr address
     * @param isOperator true/false
     */
    function setOperator(address addr, bool isOperator) external onlyOwner {
        operators[addr] = isOperator;
        emit SetOperator(addr, isOperator);
    }

    /**
     * @notice Resets the peer address (OApp instance) for a corresponding endpoint.
     * @param eid The endpoint ID.
     * @dev Only an operator or owner of the OApp can call this function.
     */
    function resetPeer(uint32 eid) external {
        require(operators[msg.sender] || msg.sender == owner(), "Not Operator");

        peers[eid] = bytes32(0);
        emit PeerSet(eid, bytes32(0));
    }

    /**
     * @notice Resets the accrued received amount for specified chain
     * @param eid The endpoint ID.
     * @dev Only owner of the OApp can call this function.
     */
    function resetReceivedTokenAmount(uint32 eid) external onlyOwner {
        delete receivedTokenAmounts[eid];
    }

    /**
     * @notice Resets the accrued sent amount for specified chain
     * @param eid The endpoint ID.
     * @dev Only owner of the OApp can call this function.
     */
    function resetSentTokenAmount(uint32 eid) external onlyOwner {
        delete sentTokenAmounts[eid];
    }

    /*//////////////////////////////////////////////////////////////
                              LZ OVERRIDE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Overwrite _debit to implement rate limits.
     * @dev Burns tokens from the sender's specified balance.
     * @param amountLD The amount of tokens to send in local decimals.
     * @param minAmountLD The minimum amount to send in local decimals.
     * @param dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     */
    function _debit(uint256 amountLD, uint256 minAmountLD, uint32 dstEid) internal override returns (uint256, uint256) {
        // _burn(msg.sender, amountSentLD)
        (uint256 amountSentLD, uint256 amountReceivedLD) = super._debit(amountLD, minAmountLD, dstEid);

        // whitelisted addresses have no limits
        if (whitelist[msg.sender]) return (amountSentLD, amountReceivedLD);

        uint256 sentTokenAmountsInThisEpoch;
        uint256 lastSentTimestamp = lastSentTimestamps[dstEid];
        uint256 currTimestamp = block.timestamp;
        
        // Round down timestamps to the nearest day. 
        if ((currTimestamp / (1 days)) > (lastSentTimestamp / (1 days))) {
            sentTokenAmountsInThisEpoch = amountSentLD;   
            lastSentTimestamps[dstEid] = currTimestamp;     
            
        } else {
            // sentTokenAmountsInThisEpoch = recentSentAmount + incomingSendAmount
            sentTokenAmountsInThisEpoch = sentTokenAmounts[dstEid] + amountSentLD;
        }

        // check against outboundLimit
        uint256 outboundLimit = outboundLimits[dstEid];
        if (sentTokenAmountsInThisEpoch > outboundLimit) revert ExceedOutboundLimit(outboundLimit, sentTokenAmountsInThisEpoch);

        // update storage
        sentTokenAmounts[dstEid] = sentTokenAmountsInThisEpoch;

        return (amountSentLD, amountReceivedLD);
    }

    
    /**
     * @dev Credits tokens to the specified address.
     * @param to The address to credit the tokens to.
     * @param amountLD The amount of tokens to credit in local decimals.
     * @param srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(address to, uint256 amountLD, uint32 srcEid) internal override returns (uint256) {
        
        uint256 amountReceivedLD = super._credit(to, amountLD, srcEid);

        // whiteslisted address have no limits
        if (whitelist[to]) return amountReceivedLD;


        uint256 receivedTokenAmountInThisEpoch;
        uint256 lastReceivedTimestamp = lastReceivedTimestamps[srcEid];
        uint256 currTimestamp = block.timestamp;

        // Round down timestamps to the nearest day. 
        if ((currTimestamp / (1 days)) > (lastReceivedTimestamp / (1 days))) {
            receivedTokenAmountInThisEpoch = amountReceivedLD;
            lastReceivedTimestamps[srcEid] = currTimestamp;

        } else {
            receivedTokenAmountInThisEpoch = receivedTokenAmounts[srcEid] + amountReceivedLD;
        }

        // ensure limit not exceeded
        uint256 inboundLimit = inboundLimits[srcEid];
        if (receivedTokenAmountInThisEpoch > inboundLimit) revert ExceedInboundLimit(inboundLimit, receivedTokenAmountInThisEpoch);

        // update storage
        receivedTokenAmounts[srcEid] = receivedTokenAmountInThisEpoch;

        return amountReceivedLD;
    } 

    /*//////////////////////////////////////////////////////////////
                              OWNABLE2STEP
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public override(Ownable, Ownable2Step) onlyOwner {
        Ownable2Step.transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal override(Ownable, Ownable2Step) {
        Ownable2Step._transferOwnership(newOwner);
    }

}
