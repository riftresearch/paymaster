// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "forge-std/console.sol";

error InvalidSafeBlock();
error BlockDoesNotExist();
error InvalidConfirmationBlock();
error InvalidProposedBlockOverwrite();

contract BlockHashStorage {
    mapping(uint256 => bytes32) blockchain; // block height => block hash
    mapping(uint256 => uint256) chainworks; // block height => chainwork
    uint256 public currentHeight;
    uint256 public currentConfirmationHeight;
    uint8 immutable minimumConfirmationDelta;

    event BlocksAdded(uint256 startBlockHeight, uint256 count);

    constructor(
        uint256 safeBlockHeight,
        uint256 safeBlockChainwork,
        bytes32 safeBlockHash,
        bytes32 retargetBlockHash,
        uint8 _minimumConfirmationDelta
    ) {
        currentHeight = safeBlockHeight;
        chainworks[safeBlockHeight] = safeBlockChainwork;
        blockchain[safeBlockHeight] = safeBlockHash;
        blockchain[calculateRetargetHeight(safeBlockHeight)] = retargetBlockHash;
        minimumConfirmationDelta = _minimumConfirmationDelta;
    }

    // Assumes that all blockHashes passed are in a chain as proven by the circuit
    function addBlock(
        uint256 safeBlockHeight,
        uint256 proposedBlockHeight,
        uint256 confirmationBlockHeight,
        bytes32[] memory blockHashes, // from safe block to confirmation block
        uint256[] memory blockChainworks,
        uint256 proposedBlockIndex // in blockHashes array
    ) internal {
        uint256 _tipBlockHeight = currentHeight;
        uint256 _tipChainwork = chainworks[currentHeight];


        // [0] ensure confirmation block matches block in blockchain (if < minimumConfirmationDelta away from proposed block)
        if (confirmationBlockHeight - proposedBlockHeight < minimumConfirmationDelta) {
            if (blockHashes[blockHashes.length - 1] != blockchain[confirmationBlockHeight]) {
                revert InvalidConfirmationBlock();
            }
        }


        // [1] validate safeBlock height
        if (safeBlockHeight > _tipBlockHeight) {
            revert InvalidSafeBlock();
        }


        // [2] return if block already exists
        if (blockchain[proposedBlockHeight] == blockHashes[proposedBlockIndex]) {
            return;
        }

        // [3] ensure proposed block is not being overwritten unless longer chain (higher confirmation chainwork)
        else if (blockchain[proposedBlockHeight] != bytes32(0) && _tipChainwork >= blockChainworks[blockChainworks.length - 1])
        {

            revert InvalidProposedBlockOverwrite();
        }


        // [4] ADDITION/OVERWRITE (proposed block > tip block)
        if (proposedBlockHeight > _tipBlockHeight) {
            // [a] ADDITION - (safe block === tip block)
            if (safeBlockHeight == _tipBlockHeight) {
                blockchain[proposedBlockHeight] = blockHashes[proposedBlockIndex];
                chainworks[proposedBlockHeight] = blockChainworks[proposedBlockIndex];
            }
            // [b] OVERWRITE - new longest chain (safe block < tip block < proposed block)
            else if (safeBlockHeight < _tipBlockHeight) {
                for (uint256 i = safeBlockHeight; i <= proposedBlockHeight; i++) {
                    blockchain[i] = blockHashes[i - safeBlockHeight];
                    chainworks[i] =  blockChainworks[i - safeBlockHeight];
                }
            }
        }

        // [5] INSERTION - (safe block < proposed block < tip block)
        else if (proposedBlockHeight < _tipBlockHeight) {
            blockchain[proposedBlockHeight] = blockHashes[proposedBlockIndex];
            chainworks[proposedBlockHeight] = blockChainworks[proposedBlockIndex];
        }


        // [6] update current height
        if (proposedBlockHeight > currentHeight) {
            currentHeight = proposedBlockHeight;
        }

        // [7] calculate what the new retarget block height should be, if it changed
        uint256 safeRetargetHeight = calculateRetargetHeight(proposedBlockHeight);
        uint256 tipRetargetHeight = calculateRetargetHeight(confirmationBlockHeight);
        if (tipRetargetHeight != safeRetargetHeight) {
          // [8] inject the retarget block hash 
          uint256 retargetHeightIndex = confirmationBlockHeight - tipRetargetHeight; 
          blockchain[tipRetargetHeight] = blockHashes[retargetHeightIndex];
          chainworks[tipRetargetHeight] = blockChainworks[retargetHeightIndex];
        }

        emit BlocksAdded(safeBlockHeight, blockHashes.length);
    }

    function validateBlockExists(uint256 blockHeight) public view {
        // check if block exists
        if (blockchain[blockHeight] == bytes32(0)) {
            revert BlockDoesNotExist();
        }
    }

    function getBlockHash(uint256 blockHeight) public view returns (bytes32) {
        return blockchain[blockHeight];
    }

    function getChainwork(uint256 blockHeight) public view returns (uint256) {
        return chainworks[blockHeight];
    }

    function calculateRetargetHeight(uint256 blockHeight) public pure returns (uint256) {
        return blockHeight - (blockHeight % 2016);
    }

}
