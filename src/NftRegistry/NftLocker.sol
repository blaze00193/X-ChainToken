// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC721 } from "node_modules/@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { OApp, Origin, MessagingFee } from "node_modules/@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { Ownable } from "node_modules/@openzeppelin/contracts/access/Ownable.sol";

import { RevertMsgExtractor } from "./../utils/RevertMsgExtractor.sol";


contract NftLocker is OApp {

    IERC721 public immutable MOCA_NFT;

    mapping(address user => UserData userData) public users;

    struct UserData {
        
        uint256 totalLocked;            // counter for next empty
        mapping(uint256 counter => uint256 tokenId) tokenIds;
    }

    // events
    event NftLocked(address indexed user, uint256 indexed tokenId, uint256 indexed totalLocked);
    event NftUnlocked(address indexed user, uint256 indexed tokenId, uint256 indexed totalLocked);

//-------------------------------constructor-------------------------------------------

    constructor(address _endpoint, address _owner, address mocaNft) OApp(_endpoint, _owner) Ownable(_owner) {
        
        MOCA_NFT = IERC721(mocaNft);
    }

   
//-------------------------------------------------------------------------------------

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/

    function lock(address onBehalfOf, uint256 tokenId, uint32 _dstEid, bytes calldata _options) external payable {
        
        // cache 
        UserData storage user = users[onBehalfOf];
        uint256 totalLocked = user.totalLocked;

        // increment & update storage
        user.tokenIds[totalLocked] = tokenId;
        user.totalLocked = ++totalLocked;
                
        emit NftLocked(onBehalfOf, tokenId, totalLocked);

        // grab
        MOCA_NFT.safeTransferFrom(onBehalfOf, address(this), tokenId);

        // Encodes message as bytes
        bytes memory _payload = abi.encode(onBehalfOf);
        
        // MessagingFee: Fee struct containing native gas and ZRO token.
        _lzSend(_dstEid, _payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));

    }


    /// @dev Allows batched call to self (this contract).
    /// @param calls An array of inputs for each call.
    function batch(bytes[] calldata calls) external payable returns (bytes[] memory results) {
        results = new bytes[](calls.length);

        for (uint256 i; i < calls.length; i++) {

            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
            results[i] = result;
        }
    }


    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    
    // returns the most recently locked tokenId
    // called by _lzReceive
    function _unlock(address onBehalfOf) internal {
        
        // cache 
        UserData storage user = users[onBehalfOf];
        uint256 totalLocked = user.totalLocked;

        // decrement & get last-in tokenId
        uint256 tokenId = user.tokenIds[--totalLocked];

        // delete tokenId
        delete user.tokenIds[totalLocked];

        emit NftUnlocked(onBehalfOf, tokenId, totalLocked);

        // return
        MOCA_NFT.safeTransferFrom(address(this), onBehalfOf, tokenId);
    }
        
    /*//////////////////////////////////////////////////////////////
                                  SEND
    //////////////////////////////////////////////////////////////*/

    // Sends a message from the source to destination chain.
    /** 
     * @dev Quotes the gas needed to pay for the full omnichain transaction.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _options // Message execution options (e.g., gas to use on destination).
     * @param onBehalfOf Nft owner address
     */
    function send(uint32 _dstEid, bytes calldata _options, address onBehalfOf) external payable {
        
        // Encodes message as bytes
        bytes memory _payload = abi.encode(onBehalfOf);

        _lzSend(_dstEid, _payload, _options, 
            MessagingFee(msg.value, 0),     // Fee struct containing native gas and ZRO token.
            payable(msg.sender)             // The refund address in case the send call reverts.
        );
    }

    /** 
     * @dev Quotes the gas needed to pay for the full omnichain transaction.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _options Message execution options
     * @param _payInLzToken boolean for which token to return fee in
     * @param onBehalfOf Nft owner address
     * @return nativeFee Estimated gas fee in native gas.
     * @return lzTokenFee Estimated gas fee in ZRO token.
     */
    function quote(uint32 _dstEid, bytes calldata _options, bool _payInLzToken, address onBehalfOf) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        
        // Encodes message as bytes
        bytes memory _payload = abi.encode(onBehalfOf);

        MessagingFee memory fee = _quote(_dstEid, _payload, _options, _payInLzToken);
        return (fee.nativeFee, fee.lzTokenFee);
    }


    /*//////////////////////////////////////////////////////////////
                                RECEIVE
    //////////////////////////////////////////////////////////////*/


    /**
     * @param _origin struct containing info about the message sender
     * @param _guid global packet identifier
     * @param _payload message payload being received
     * @param _executor the Executor address.
     * @param _extraData arbitrary data appended by the Executor
     */
    function _lzReceive(Origin calldata _origin, bytes32 _guid, bytes calldata _payload, address _executor, bytes calldata _extraData) internal virtual override {

        // decode message
        address owner = abi.decode(_payload, (address));

        _unlock(owner);
    }


    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    // admin can call unlock on a specific user in special cases
    // admin must ensure that in unlocking manually, Registry is updated as well 
    // this can be done via send() xchain msg or directly on the polygon contract
    function unlock(address onBehalfOf) external onlyOwner {
        _unlock(onBehalfOf);
    }

}

