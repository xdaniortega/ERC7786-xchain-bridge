// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AttributeLib
 * @dev Library for handling message attributes in the cross-chain bridge
 */
library AttributeLib {
    /// @notice Represents a key-value pair attribute that can be attached to a message
    struct Attribute {
        bytes4 key;
        bytes value;
    }

    /// @notice Attribute keys for different types of attributes
    bytes4 constant IMPACT_KEY = bytes4(keccak256("IMPACT")); // Impact level of the transfer

    /// @notice Decodes an attribute from its encoded form
    /// @param encodedAttribute The encoded attribute bytes
    /// @return The decoded Attribute struct
    function decodeAttribute(bytes memory encodedAttribute) internal pure returns (Attribute memory) {
        return abi.decode(encodedAttribute, (Attribute));
    }

    /// @notice Gets the value of an attribute by its key
    /// @param attributes The array of encoded attributes
    /// @param key The key to look for
    /// @return The decoded value if found, empty bytes if not found
    function getAttributeValue(bytes[] memory attributes, bytes4 key) internal pure returns (bytes memory) {
        for (uint i = 0; i < attributes.length; i++) {
            Attribute memory attr = decodeAttribute(attributes[i]);
            if (attr.key == key) {
                return attr.value;
            }
        }
        return "";
    }
}
