// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


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

    mapping(address => bool) public isAttestor;
    address[] public attestorsList;
    uint256 public signatureThreshold;

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
    error InvalidThreshold();
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

    constructor(address[] memory _initialAttestors, uint256 _threshold, address initialOwner) Ownable(initialOwner) {
        if (_threshold == 0) revert InvalidThreshold();
        if (_threshold > _initialAttestors.length) revert InvalidThreshold();

        _addAttestors(_initialAttestors);
        signatureThreshold = _threshold;
        emit ThresholdChanged(_threshold);
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


    function attestMessage(bytes32 _messageId, bytes memory _signature) public onlyAttestor {
        AttestationData storage status = attestations[_messageId];
        if (status.hasAttested[msg.sender]) revert AlreadyAttested();

        bytes32 messageHashToVerify = _messageId.toEthSignedMessageHash(); // Prepara el hash según EIP-191
        address signer = messageHashToVerify.recover(_signature);

        if (signer != msg.sender) revert InvalidSignature();

        status.hasAttested[msg.sender] = true;
        status.numAttestations++;

        emit MessageAttested(_messageId, msg.sender, status.numAttestations);

        if (status.numAttestations == signatureThreshold) {
            emit AttestationConsensusReached(_messageId);

            //todo: call the execute funtion
        }
    }
}