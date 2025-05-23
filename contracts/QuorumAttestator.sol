// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {AttributeLib} from "./libraries/AttributeLib.sol";

/**
 * @title QuorumAttestator
 * @dev Allows a group of attestators to sign messages and reach a consensus.
 *       NOTE: I didn't implement removal or update of threshold.
 *       BitMap can be used to save gas on struct AttestationData.
 * @author Daniel Ortega
 */
contract QuorumAttestator is Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using AttributeLib for bytes[];

    mapping(address => bool) public isAttestor;
    address[] public attestorsList;

    event MessageAttested(
        bytes32 indexed messageId,
        address indexed attestor,
        uint256 currentAttestationCount
    );
    event AttestationConsensusReached(bytes32 indexed messageId);
    event AttestorAdded(address indexed attestor);

    error NotAttestor();
    error AlreadyAttested();
    error InvalidSignature();
    error AttestorAlreadyExists();
    error AttestorNotFound();
    error ZeroAddress();

    struct AttestationData {
        mapping(address => bool) hasAttested; // attestor => bool // TODO: we can upgrade to bitMap
        uint256 numAttestations;
    }
    mapping(bytes32 => AttestationData) public attestations; // messageId => AttestationData
    
    modifier onlyAttestor() {
        if (!isAttestor[msg.sender]) revert NotAttestor();
        _;
    }

    constructor(address[] memory _initialAttestors, address initialOwner) Ownable(initialOwner) {
        _addAttestor(_initialAttestors);
    }

    function _addAttestor(address[] memory _attestors) internal {
        for (uint256 i = 0; i < _attestors.length; i++) {
            address attestor = _attestors[i];
            if (attestor == address(0)) revert ZeroAddress();
            if (isAttestor[attestor]) revert AttestorAlreadyExists();
            isAttestor[attestor] = true;
            attestorsList.push(attestor);
            emit AttestorAdded(attestor);
        }
    }

    /// @notice Assigns the number of required signatures based on message attributes
    /// @param attributes The array of encoded attributes from the message
    /// @return The number of required signatures (1 for low impact, 2 for high impact)
    function assignThresholdSignatures(bytes[] calldata attributes) external pure returns (uint256) {
        bytes memory impactValue = attributes.getAttributeValue(AttributeLib.IMPACT_KEY);
        if (impactValue.length == 0) {
            return 1; // Default to low impact if no impact attribute found
        }
        
        string memory impact = abi.decode(impactValue, (string));
        if (keccak256(bytes(impact)) == keccak256(bytes("high"))) {
            return 2; // High impact requires 2 signatures
        }
        return 1; // Low impact requires 1 signature
    }

    function attestMessage(bytes32 _messageId, bytes memory _signature) public onlyAttestor {
        AttestationData storage status = attestations[_messageId];
        if (status.hasAttested[msg.sender]) revert AlreadyAttested();

        bytes32 messageHashToVerify = _messageId.toEthSignedMessageHash(); // Prepara el hash según EIP-191
        address signer = messageHashToVerify.recover(_signature);

        if (signer != msg.sender) revert InvalidSignature();

        status.hasAttested[msg.sender] = true;
        status.numAttestations++;

        emit MessageAttested(_messageId, msg.sender, status.numAttestations);
    }

    function isSigner(address _attestor) public view returns (bool) {
        return isAttestor[_attestor];
    }

    function getAttestationsReached(bytes32 _messageId) public view returns (uint256) {
        return attestations[_messageId].numAttestations;
    }
}