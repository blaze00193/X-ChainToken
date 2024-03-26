// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { OFT } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { EIP3009 } from "./EIP3009.sol";
import { EIP712 } from "./utils/EIP712.sol";

// LZ Structs
import { Origin } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { SendParam, MessagingFee, MessagingReceipt, OFTReceipt } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

//Note: To be deployed everywhere else, outside of the home chain
//      18 dp
contract MocaOFT is OFT, EIP3009, Ownable2Step {

    string internal constant _version = "v1";
    
    // MocaToken has a fixed total supply of 8_888_888_888 * 1e18
    uint256 internal constant TOTAL_GLOBAL_SUPPLY = 8_888_888_888 ether;

    // Outbound limits
    mapping(uint32 eid => uint256 outboundLimit) public outboundLimits;
    mapping(uint32 eid => uint256 sentTokenAmountsInThisEpoch) public sentTokenAmounts;
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
    error ExceedGlobalSupply(uint256 currentOftSupply, uint256 incomingMintAmount);
    error SendAndCallBlocked();

    /**
     * @param name token name
     * @param symbol token symbol
     * @param lzEndpoint LayerZero Endpoint address
     * @param delegate The address capable of making OApp configurations inside of the endpoint.
     * @param owner token owner
     */
    constructor(string memory name, string memory symbol, address lzEndpoint, address delegate, address owner) 
        OFT(name, symbol, lzEndpoint, delegate) Ownable(owner) {
        
        _DEPLOYMENT_CHAINID = block.chainid; 
        _DOMAIN_SEPARATOR = EIP712.makeDomainSeparator(name, _version);
    }

    /*//////////////////////////////////////////////////////////////
                                 EIP721
    //////////////////////////////////////////////////////////////*/

    function _domainSeparator() internal override view returns (bytes32) {
        return block.chainid == _DEPLOYMENT_CHAINID ? _DOMAIN_SEPARATOR : EIP712.makeDomainSeparator(name(), _version);

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
     * @param eid Destination eid 
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
        // ensure not minting in excess of global token supply
        uint256 totalSupply = totalSupply();
        if(totalSupply + amountLD > TOTAL_GLOBAL_SUPPLY) revert ExceedGlobalSupply(totalSupply, amountLD);

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


    /**
     * @dev Executes the send operation.
     * @param _sendParam The parameters for the send operation.
     * @param _fee The calculated fee for the send() operation.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @param _refundAddress The address to receive any excess funds.
     * @return msgReceipt The receipt for the send operation.
     * @return oftReceipt The OFT receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     */
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress) external payable override returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        // @dev Applies the token transfers regarding this send() operation.
        // - amountSentLD is the amount in local decimals that was ACTUALLY sent from the sender.
        // - amountReceivedLD is the amount in local decimals that will be credited to the recipient on the remote OFT instance.
        (uint256 amountSentLD, uint256 amountReceivedLD) = _debit(
            _sendParam.amountLD,
            _sendParam.minAmountLD,
            _sendParam.dstEid
        );

        // @dev Builds the options and OFT message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_sendParam, amountReceivedLD);

        // block sendAndCall
        if(isComposed(message)) revert SendAndCallBlocked(); 

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_sendParam.dstEid, message, options, _fee, _refundAddress);
        // @dev Formulate the OFT receipt.
        oftReceipt = OFTReceipt(amountSentLD, amountReceivedLD);

        emit OFTSent(msgReceipt.guid, _sendParam.dstEid, msg.sender, amountSentLD);
    }

    /** 
     * @dev Checks if the OFT message is composed. Copied from OFTMsgCodec.sol
     * @param _msg The OFT message.
     * @return A boolean indicating whether the message is composed.
     */
    function isComposed(bytes memory _msg) internal pure returns (bool) {
        // uint8 private constant SEND_AMOUNT_SD_OFFSET = 40;
        // return _msg.length > SEND_AMOUNT_SD_OFFSET
        return _msg.length > 40;
    }

    /*//////////////////////////////////////////////////////////////
                                EIP3009
    //////////////////////////////////////////////////////////////*/

    
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