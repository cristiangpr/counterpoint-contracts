// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

import "hardhat/console.sol";

/// ERRORS
error ValueLessThanFee(uint256 fee, uint256 value);
error HashAlreadySaved(bytes32 metahash);
error UnexpectedRequestID(bytes32 requestId);
error RequestStillInProgress(address user, bytes32 requestId);

contract Authentichain is FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;
    uint256 public fee;
    address payable public owner;
    mapping(bytes32 => bytes32) public metaHashToDataHash;
    mapping(bytes32 => Metadata) public metaHashToMetadata;
    mapping(address => bytes32) public userLastRequestId;
    mapping(address => bool) userRequestInProgress;
    address router = 0xC22a79eBA640940ABB6dF0f7982cc119578E11De;

    //Callback gas limit
    uint32 gasLimit = 300000;

    // donID - Hardcoded for Sepolia
    // Check to get the donID for your supported network https://docs.chain.link/chainlink-functions/supported-networks
    bytes32 donID =
        0x66756e2d706f6c79676f6e2d616d6f792d310000000000000000000000000000;

    struct Metadata {
        string gpsLongitude;
        string gpsLatitude;
        string gpsLongitudeRef;
        string gpsLatitudeRef;
        uint256 timestamp;
        uint256 size;
        string format;
    }

    event Withdrawal(uint amount, uint when);
    event HashSaved(address sender, Metadata metadata);
    event Response(bytes32 indexed requestId, bytes response, bytes err);

    constructor(uint256 _fee) payable FunctionsClient(router) {
        owner = payable(msg.sender);
        fee = _fee;
    }

    /**
     * @notice Sends an HTTP request for character information
     * @param subscriptionId The ID for the Chainlink subscription
     * @param args The arguments to pass to the HTTP request
     * @return requestId The ID of the request
     */
    function sendRequest(
        string calldata source,
        uint64 subscriptionId,
        string[] calldata args
    ) external returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        if (args.length > 0) req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
        userLastRequestId[msg.sender] = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );
        userRequestInProgress[msg.sender] = true;

        return userLastRequestId[msg.sender];
    }

    /**
     * @notice Callback function for fulfilling a request
     * @param requestId The ID of the request to fulfill
     * @param response The HTTP response data
     * @param err Any errors from the Functions request
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        // Emit an event to log the response
        emit Response(requestId, response, err);
        userRequestInProgress[msg.sender] = false;
    }

    function saveHash(
        Metadata calldata metadata,
        string calldata data,
        bytes32 requestId
    ) external payable {
        if (userLastRequestId[msg.sender] != requestId) {
            revert UnexpectedRequestID(requestId); // Check if request IDs match
        }
        if (userRequestInProgress[msg.sender] == true) {
            revert RequestStillInProgress(msg.sender, requestId);
        }
        if (msg.value < fee) {
            revert ValueLessThanFee(fee, msg.value);
        }

        bytes32 metaHash = keccak256(abi.encode(metadata));

        if (metaHashToDataHash[metaHash] != 0) {
            revert HashAlreadySaved(metaHash);
        }
        bytes32 dataHash = keccak256(abi.encode(data));
        metaHashToDataHash[metaHash] = dataHash;
        metaHashToMetadata[metaHash] = metadata;
        emit HashSaved(msg.sender, metadata);
    }

    function authenticate(
        Metadata calldata metaData,
        string calldata data
    ) external view returns (bool) {
        bytes32 metaHash = keccak256(abi.encode(metaData));
        if (keccak256(abi.encode(data)) == metaHashToDataHash[metaHash]) {
            return true;
        } else {
            return false;
        }
    }

    function withdraw() public {
        require(msg.sender == owner, "You aren't the owner");

        emit Withdrawal(address(this).balance, block.timestamp);

        owner.transfer(address(this).balance);
    }

    function getDataHash(
        Metadata calldata metadata
    ) external view returns (bytes32 dataHash) {
        bytes32 metaHash = keccak256(abi.encode(metadata));
        return metaHashToDataHash[metaHash];
    }

    function getMetaData(
        bytes32 metaHash
    ) external view returns (Metadata memory metaData) {
        return metaHashToMetadata[metaHash];
    }
}
