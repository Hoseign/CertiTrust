// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract CertiTrust {
    struct Certificate {
        string studentName;
        string courseName;
        string issueDate;
        string certHash;
        bool isValid;
    }

    mapping(string => Certificate) public certificates;
    address public owner;

    event CertificateIssued(string indexed certHash, string studentName);
    event CertificateRevoked(string indexed certHash);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this act");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function issueCertificate(
        string memory _certHash,
        string memory _studentName,
        string memory _courseName,
        string memory _issueDate
    ) public onlyOwner {
        certificates[_certHash] = Certificate(_studentName, _courseName, _issueDate, _certHash, true);
        emit CertificateIssued(_certHash, _studentName);
    }

    function verifyCertificate(
        string memory _certHash
    ) public view returns (string memory, string memory, string memory, bool) {
        Certificate memory cert = certificates[_certHash];
        return (cert.studentName, cert.courseName, cert.issueDate, cert.isValid);
    }

    function revokeCertificate(string memory _certHash) public onlyOwner {
        certificates[_certHash].isValid = false;
        emit CertificateRevoked(_certHash);
    }
}
