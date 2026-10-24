// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract CertiTrustRegistry {
    struct Credential {
        bytes32 studentIdHash;
        bytes32 documentHash;
        uint64 issuedAt;
        bool exists;
    }

    address public owner;

    mapping(bytes32 documentIdHash => Credential) private credentials;
    mapping(bytes32 documentHash => bytes32 documentIdHash) private documentByHash;

    event CertificateIssued(
        bytes32 indexed documentIdHash,
        bytes32 indexed documentHash,
        bytes32 studentIdHash,
        uint64 issuedAt
    );
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can issue certificates");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function issueCertificate(
        bytes32 documentIdHash,
        bytes32 studentIdHash,
        bytes32 documentHash
    ) external onlyOwner {
        require(documentIdHash != bytes32(0), "Document ID hash is required");
        require(studentIdHash != bytes32(0), "Student ID hash is required");
        require(documentHash != bytes32(0), "Document hash is required");
        require(!credentials[documentIdHash].exists, "Document ID already issued");
        require(documentByHash[documentHash] == bytes32(0), "Document hash already issued");

        uint64 issuedAt = uint64(block.timestamp);
        credentials[documentIdHash] = Credential({
            studentIdHash: studentIdHash,
            documentHash: documentHash,
            issuedAt: issuedAt,
            exists: true
        });
        documentByHash[documentHash] = documentIdHash;

        emit CertificateIssued(documentIdHash, documentHash, studentIdHash, issuedAt);
    }

    function verifyCertificate(
        bytes32 documentIdHash,
        bytes32 documentHash
    ) external view returns (bool) {
        Credential memory credential = credentials[documentIdHash];
        return credential.exists && credential.documentHash == documentHash;
    }

    function isHashIssued(bytes32 documentHash) external view returns (bool) {
        bytes32 documentIdHash = documentByHash[documentHash];
        return documentIdHash != bytes32(0) && credentials[documentIdHash].exists;
    }

    function getCredential(
        bytes32 documentIdHash
    ) external view returns (bytes32 studentIdHash, bytes32 documentHash, uint64 issuedAt, bool exists) {
        Credential memory credential = credentials[documentIdHash];
        return (
            credential.studentIdHash,
            credential.documentHash,
            credential.issuedAt,
            credential.exists
        );
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is required");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}