//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {GoblinDistributor} from "../src/GoblinDistributor.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract GoblinDistributorTest is Test {
    address public OWNER = makeAddr("owner");
    address public USER = makeAddr("user");

    GoblinDistributor goblin;
    ERC20Mock usdc;

    function setUp() public {
        vm.startPrank(OWNER);
        usdc = new ERC20Mock();
        goblin = new GoblinDistributor(address(usdc), block.timestamp + 1 days, block.timestamp + 8 days);
        vm.stopPrank();
        assertEq(goblin.owner(), OWNER);
    }

    modifier getCurrency() {
        vm.startPrank(OWNER);
        usdc.mint(OWNER, 1000 ether);
        usdc.mint(USER, 1000 ether);
        vm.stopPrank();
        _;
    }

    //////////////////
    // Setter Tests //
    //////////////////

    function testSetKeeperWorksFromOwnerAddress() public {
        vm.prank(OWNER);
        goblin.setKeeper(USER, true);
        assertEq(goblin.isKeeper(USER), true);
    }

    function testSetKeeperFailsIfCallerIsntOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        goblin.setKeeper(USER, true);
    }

    function testSetKeeperLetsOwnerRevokeKeeperAccess() public {
        vm.prank(OWNER);
        goblin.setKeeper(USER, true);
        assertEq(goblin.isKeeper(USER), true);
        vm.prank(OWNER);
        goblin.setKeeper(USER, false);
        assertEq(goblin.isKeeper(USER), false);
    }

    ////////////////////////
    // Top Up Funds Tests //
    ///////////////////////

    function testTopUpFundsWorksAsExpected() public getCurrency {
        vm.startPrank(OWNER);
        usdc.approve(address(goblin), 100 ether);
        goblin.topUpFunds(1 ether);
        vm.stopPrank();
        assertEq(goblin.getContractRewardBalance(), 1 ether);
    }

    function testTopUpFundsFailsFromNonKeeper() public getCurrency {
        vm.startPrank(USER);
        usdc.approve(address(goblin), 100 ether);
        vm.expectRevert();
        goblin.topUpFunds(1 ether);
        vm.stopPrank();
    }

    function testTopUpFundsWorksFromKeepers() public getCurrency {
        vm.prank(OWNER);
        goblin.setKeeper(USER, true);
        vm.startPrank(USER);
        usdc.approve(address(goblin), 100 ether);
        goblin.topUpFunds(1 ether);
        vm.stopPrank();
        assertEq(goblin.getContractRewardBalance(), 1 ether);
    }

    function testTopUpFundsFailsIfInsufficientFunds() public {
        vm.startPrank(OWNER);
        usdc.approve(address(goblin), 100 ether);
        vm.expectRevert();
        goblin.topUpFunds(1 ether);
        vm.stopPrank();
    }

    function testTopUpFundsFailsIfNoApproval() public getCurrency {
        vm.prank(OWNER);
        vm.expectRevert();
        goblin.topUpFunds(1 ether);
    }

    event RewardsAdded(uint256 indexed amount);

    function testTopUpFundsEmitsAnEventIfSuccessful() public getCurrency {
        vm.startPrank(OWNER);
        usdc.approve(address(goblin), 100 ether);
        vm.expectEmit();
        emit RewardsAdded(1 ether);
        goblin.topUpFunds(1 ether);
    }

    ////////////////////////
    // Withdraw All Tests //
    ///////////////////////

    event RewardsWithdrawn(uint256 indexed amount);

    function testWithdrawAllWorksAsExpectedFromOwner() public getCurrency {
        vm.startPrank(OWNER);
        usdc.approve(address(goblin), 100 ether);
        goblin.topUpFunds(1 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.prank(OWNER);
        vm.expectEmit();
        emit RewardsWithdrawn(1 ether);
        goblin.withdrawAll(address(usdc));

        assertEq(goblin.getContractRewardBalance(), 0);
    }

    function testWithdrawAllFailsFromNonOwner() public getCurrency {
        vm.startPrank(OWNER);
        usdc.approve(address(goblin), 100 ether);
        goblin.topUpFunds(1 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.prank(USER);
        vm.expectRevert();
        goblin.withdrawAll(address(usdc));
    }

    function testWithdrawAllFailsIfClaimingNotOver() public getCurrency {
        vm.startPrank(OWNER);
        usdc.approve(address(goblin), 100 ether);
        goblin.topUpFunds(1 ether);
        vm.stopPrank();

        vm.prank(OWNER);
        vm.expectRevert();
        goblin.withdrawAll(address(usdc));
    }

    function testWithdrawAllFailsIfContractBalanceIsZero() public getCurrency {
        vm.warp(block.timestamp + 8 days);

        vm.prank(OWNER);
        vm.expectRevert();
        goblin.withdrawAll(address(usdc));
    }

    ///////////////////////
    // Add Winners Tests //
    ///////////////////////

    event WinnersAdded(uint256 indexed timestamp, uint256 indexed addedRewards);

    function testAddWinnersLetsKeepersAddWinners() public getCurrency {
        // Have to warp past cooldown period as timestamp starts at 0
        vm.warp(block.timestamp + 301);

        vm.prank(OWNER);
        goblin.setKeeper(USER, true);

        address[] memory addressArray = new address[](1);
        addressArray[0] = USER;
        uint256[] memory uintArray = new uint256[](1);
        uintArray[0] = 1 ether;

        vm.startPrank(USER);
        vm.expectEmit();
        emit WinnersAdded(block.timestamp, 1 ether);
        goblin.addWinners(addressArray, uintArray);
        vm.stopPrank();
        assertEq(goblin.rewards(USER), 1 ether);
    }

    function testAddWinnersFailsFromNonKeeper() public getCurrency {
        // Have to warp past cooldown period as timestamp starts at 0
        vm.warp(block.timestamp + 301);

        address[] memory addressArray = new address[](1);
        addressArray[0] = USER;
        uint256[] memory uintArray = new uint256[](1);
        uintArray[0] = 1 ether;

        vm.prank(USER);
        vm.expectRevert();
        goblin.addWinners(addressArray, uintArray);
    }

    function testAddWinnersWithHugeArrays() public getCurrency {
        // Have to warp past cooldown period as timestamp starts at 0
        vm.warp(block.timestamp + 301);

        vm.prank(OWNER);
        goblin.setKeeper(USER, true);

        address[] memory addressArray = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            addressArray[i] = USER;
        }
        uint256[] memory uintArray = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            uintArray[i] = 1 ether;
        }

        vm.startPrank(USER);
        vm.expectEmit();
        emit WinnersAdded(block.timestamp, 100 ether);
        goblin.addWinners(addressArray, uintArray);
        vm.stopPrank();
        assertEq(goblin.rewards(USER), 100 ether);
    }

    function testAddWinnersWithMultipleUsers() public getCurrency {
        vm.warp(block.timestamp + 301);

        vm.prank(OWNER);
        goblin.setKeeper(USER, true);

        address[] memory addressArray = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            if (i % 2 == 0) {
                addressArray[i] = USER;
            } else {
                addressArray[i] = OWNER;
            }
        }
        uint256[] memory uintArray = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            uintArray[i] = 1 ether;
        }
        vm.startPrank(USER);
        vm.expectEmit();
        emit WinnersAdded(block.timestamp, 100 ether);
        goblin.addWinners(addressArray, uintArray);
        vm.stopPrank();

        assertEq(goblin.rewards(USER), 50 ether);
        assertEq(goblin.rewards(OWNER), 50 ether);
    }

    /////////////////////////
    // Claim Rewards Tests //
    /////////////////////////

    event RewardsClaimed(address indexed user, uint256 amount);

    modifier addRewards() {
        vm.warp(block.timestamp + 301);

        vm.startPrank(OWNER);
        goblin.setKeeper(USER, true);
        usdc.approve(address(goblin), 100 ether);
        goblin.topUpFunds(100 ether);
        vm.stopPrank();

        address[] memory addressArray = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            addressArray[i] = USER;
        }
        uint256[] memory uintArray = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            uintArray[i] = 1 ether;
        }

        vm.startPrank(USER);
        goblin.addWinners(addressArray, uintArray);
        vm.stopPrank();
        assertEq(goblin.rewards(USER), 100 ether);
        _;
    }

    function testClaimRewardsLetsUsersClaimRewardsTheCorrectAmountOfRewards() public getCurrency {
        vm.warp(block.timestamp + 301);

        vm.prank(OWNER);
        goblin.setKeeper(USER, true);

        address[] memory addressArray = new address[](1);
        addressArray[0] = USER;
        uint256[] memory uintArray = new uint256[](1);
        uintArray[0] = 1 ether;

        vm.startPrank(USER);
        goblin.addWinners(addressArray, uintArray);
        vm.stopPrank();
        assertEq(goblin.rewards(USER), 1 ether);

        vm.startPrank(OWNER);
        usdc.approve(address(goblin), 100 ether);
        goblin.topUpFunds(100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(USER);
        vm.expectEmit();
        emit RewardsClaimed(USER, 1 ether);
        goblin.claimRewards();
        assertEq(usdc.balanceOf(address(goblin)), 99 ether);
    }

    function testClaimRewardsRevertsIfUserBlacklisted() public getCurrency addRewards {
        vm.prank(OWNER);
        goblin.setBlacklisted(USER, true);
        vm.warp(block.timestamp + 1 days);
        vm.prank(USER);
        vm.expectRevert();
        goblin.claimRewards();
    }

    function testClaimRewardsRevertsIfClaimingPeriodNotOpen() public getCurrency addRewards {
        vm.prank(USER);
        vm.expectRevert();
        goblin.claimRewards();

        vm.warp(block.timestamp + 8 days);
        vm.prank(USER);
        vm.expectRevert();
        goblin.claimRewards();
    }

    function testClaimRewardsFailsIfRewardsAreEmpty() public getCurrency addRewards {
        vm.warp(block.timestamp + 1 days);
        vm.prank(OWNER);
        vm.expectRevert();
        goblin.claimRewards();
    }

    function testClaimRewardsFailsIfContractHasInsufficientFunds() public getCurrency {
        vm.warp(block.timestamp + 301);

        vm.startPrank(OWNER);
        goblin.setKeeper(USER, true);
        usdc.approve(address(goblin), 100 ether);
        goblin.topUpFunds(100 ether);
        vm.stopPrank();

        address[] memory addressArray = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            addressArray[i] = USER;
        }
        uint256[] memory uintArray = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            uintArray[i] = 2 ether;
        }

        vm.startPrank(USER);
        goblin.addWinners(addressArray, uintArray);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(USER);
        vm.expectRevert();
        goblin.claimRewards();
    }

    function testClaimRewardsDecrementsTotalClaimableFunds() public getCurrency addRewards {
        vm.warp(block.timestamp + 1 days);
        vm.prank(USER);
        goblin.claimRewards();
        assertEq(goblin.totalClaimableRewards(), 0 ether);
    }

    function testClaimRewardsIncreasesUsersUsdcBalance() public getCurrency addRewards {
        uint256 balBefore = usdc.balanceOf(USER);
        vm.warp(block.timestamp + 1 days);
        vm.prank(USER);
        goblin.claimRewards();
        uint256 balAfter = usdc.balanceOf(USER);
        assertEq(balAfter - balBefore, 100 ether);
    }

    //////////////////
    // Getter Tests //
    //////////////////

    function testGetRewardsReturnsUsersTotalAvailableRewards() public getCurrency addRewards {
        assertEq(goblin.rewards(USER), 100 ether);
    }

    function testGetIsClaimingLiveReturnsWhetherClaimingIsLive() public {
        assertEq(goblin.getIsClaimingLive(), false);
        vm.warp(block.timestamp + 1 days);
        assertEq(goblin.getIsClaimingLive(), true);
    }

    function testGetContractRewardBalance() public getCurrency addRewards {
        assertEq(goblin.getContractRewardBalance(), 100 ether);
    }
}
