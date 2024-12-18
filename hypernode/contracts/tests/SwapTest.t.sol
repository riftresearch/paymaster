// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ExchangeTestBase} from "./ExchangeTestBase.t.sol";
import {RiftExchange} from "../src/RiftExchange.sol";

contract SwapTest is ExchangeTestBase {
    function depositLiquidity() public {
        deal(address(usdt), lp1, 1000e6); // Mint 1k USDT for lp1
        vm.startPrank(lp1);
        usdt.approve(address(riftExchange), 1000e6);

        // deposit liquidit
        riftExchange.depositLiquidity(
            // 1000 USDT
            1000e6,
            596302900000000,
            0x001463dff5f8da08ca226ba01f59722c62ad9b9b3eaa,
            -1,
            -1
        );
        console.log("Liquidity Deposited...");
        vm.stopPrank();
    }

    function testSwapEndtoEndFreshContract() public {
        depositLiquidity();
        uint192 amountOut = 100e6;
        uint256 protocolFee = uint256((amountOut * uint192(riftExchange.protocolFeeBP())) / 10000);
        vm.startPrank(testAddress);
        // Get some USDT for reservation fees, approve it for the exchange
        //deal(address(usdt), testAddress, 3.1e6);
        //usdt.approve(address(riftExchange), 3.1e6);

        // Get the balance USDT before the swap for the testAddress
        uint256 balanceBefore = usdt.balanceOf(testAddress);

        // Reserve Liquidity
        vm.startPrank(testAddress);
        uint256[] memory vaultIndexesToReserve = new uint256[](1);
        vaultIndexesToReserve[0] = 0;
        uint192[] memory amountsToReserve = new uint192[](1);
        amountsToReserve[0] = amountOut;
        uint256[] memory noOverwrites = new uint256[](0);
        riftExchange.reserveLiquidity(msg.sender, vaultIndexesToReserve, amountsToReserve, testAddress, 0, noOverwrites);

        vm.stopPrank();

        // Get balance of the hypernode before all onchain interactions
        uint256 balanceHypernodeBefore = usdt.balanceOf(hypernode1);

        // Propose a proof
        bytes memory proof = abi.encodePacked(hex"deadbeef");
        bytes32[] memory subsetblockHashes = new bytes32[](7);
        subsetblockHashes[0] = blockHashes[0];
        subsetblockHashes[1] = blockHashes[1];
        subsetblockHashes[2] = blockHashes[2];
        subsetblockHashes[3] = blockHashes[3];
        subsetblockHashes[4] = blockHashes[4];
        subsetblockHashes[5] = blockHashes[5];
        subsetblockHashes[6] = blockHashes[6];

        uint256[] memory subsetblockChainworks = new uint256[](7);
        subsetblockChainworks[0] = blockChainworks[0];
        subsetblockChainworks[1] = blockChainworks[1];
        subsetblockChainworks[2] = blockChainworks[2];
        subsetblockChainworks[3] = blockChainworks[3];
        subsetblockChainworks[4] = blockChainworks[4];
        subsetblockChainworks[5] = blockChainworks[5];
        subsetblockChainworks[6] = blockChainworks[6];

        vm.startPrank(hypernode1);

        vm.warp(1726339441);

        riftExchange.proposeTransactionProof({
            swapReservationIndex: 0,
            bitcoinTxId: keccak256(hex"beef"),
            merkleRoot: keccak256(hex"dead"),
            safeBlockHeight: uint32(blockHeights[0]),
            proposedBlockHeight: blockHeights[1],
            confirmationBlockHeight: blockHeights[6],
            blockHashes: subsetblockHashes,
            blockChainworks: subsetblockChainworks,
            proof: proof
        });

        // Simulate 10 minutes passing
        vm.warp(1726339441 + 600);

        // Release Liquidity
        riftExchange.releaseLiquidity(0);

        vm.stopPrank();

        // Assert balance of the buyer
        uint256 balance = usdt.balanceOf(testAddress);
        console.log("Balance before swap: ", balanceBefore);
        console.log("Balance after swap:  ", balance);
        assertEq(balance, amountOut-protocolFee, "Balance should be equal to amountOut");

        // Balance increase of the hypernode
        uint256 balanceHypernodeAfter = usdt.balanceOf(hypernode1);
        console.log("Balance of hypernode before swap: ", balanceHypernodeBefore);
        console.log("Balance of hypernode after swap:  ", balanceHypernodeAfter);
        assertEq(balanceHypernodeAfter - balanceHypernodeBefore, 3e6, "Hypernode balance should increase by 3 USDT");
    }
}
