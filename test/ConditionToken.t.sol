// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionToken} from "../src/ConditionToken.sol";

contract TokenDeployer {
    function deploy() external returns (ConditionToken) {
        return new ConditionToken();
    }
}

contract ConditionTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    ConditionToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new ConditionToken();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_MetadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "CONDITIONALS");
        assertEq(token.symbol(), "CONDITION");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsOneMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        ConditionToken deployed = new ConditionToken();
        assertEq(deployed.balanceOf(address(this)), SUPPLY);
    }

    function test_ContractDeployerReceivesSupplyInsteadOfTransactionOrigin() public {
        TokenDeployer factory = new TokenDeployer();
        vm.prank(alice, alice);
        ConditionToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 23 ether);
        assertTrue(token.transfer(alice, 23 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 23 ether);
        assertEq(token.balanceOf(alice), 23 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupplyAndTransferBack() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferRejectsInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferRejectsZeroRecipientEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventOverwritesAndRevokes() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 10 ether);
        assertTrue(token.approve(spender, 10 ether));
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertTrue(token.approve(spender, 4 ether));
        assertEq(token.allowance(address(this), spender), 4 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApprovalDoesNotRequireTokensAndIsScopedToSpender() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromSpendsOnlyApprovedAmount() public {
        token.approve(spender, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 4 ether));
        assertEq(token.allowance(address(this), spender), 6 ether);
        assertEq(token.balanceOf(alice), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 6 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 6 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceRemainsUnchanged() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    function test_TransferFromRejectsUnapprovedSpender() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 10 ether);
    }

    function test_TransferFromRejectsInsufficientAllowance() public {
        token.approve(spender, 3);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 3, 4));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        assertEq(token.allowance(address(this), spender), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevokedSpenderCannotTransfer() public {
        token.approve(spender, 10);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_TransferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromZeroRecipientRestoresAllowance() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromRejectsZeroSender() public {
        // Allowance spending validates the approver before reaching transfer's sender check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromSelfStillConsumesAllowance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 10);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 10));
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_HolderTransferFromRequiresApprovalToo() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_LaunchDistributionAndTradingTransfersAreExact() public {
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("poolManager");
        address requester = makeAddr("requester");
        token.transfer(distributor, SUPPLY / 10);
        token.transfer(poolManager, SUPPLY * 8 / 10);
        token.transfer(requester, SUPPLY / 10);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(poolManager), SUPPLY * 8 / 10);
        assertEq(token.balanceOf(requester), SUPPLY / 10);
        vm.prank(distributor);
        token.transfer(alice, SUPPLY / 10);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(alice), SUPPLY / 10);
        vm.prank(poolManager);
        token.transfer(bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        vm.prank(bob);
        token.transfer(poolManager, 100 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(poolManager), SUPPLY * 8 / 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        token.transfer(alice, 100 ether);
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "transferOwnership(address)",
            "initialize(address)",
            "upgradeTo(address)",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, 1);
            (bool deployerSuccess,) = address(token).call(data);
            assertFalse(deployerSuccess, signatures[i]);
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(data);
            assertFalse(strangerSuccess, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function testFuzz_TransfersConserveSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverspendingAlwaysReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_TransferFromEnforcesAllowanceAndBalance(uint256 approved, uint256 amount) public {
        approved = approved == type(uint256).max ? approved : bound(approved, 0, SUPPLY + 1);
        amount = bound(amount, 0, SUPPLY + 1);
        token.approve(spender, approved);
        if (amount > approved) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            );
        } else if (amount > SUPPLY) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
            );
        }
        vm.prank(spender);
        bool success = token.transferFrom(address(this), alice, amount);
        if (amount <= approved && amount <= SUPPLY) {
            assertTrue(success);
            uint256 remaining = approved == type(uint256).max ? approved : approved - amount;
            assertEq(token.allowance(address(this), spender), remaining);
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        } else {
            assertEq(token.allowance(address(this), spender), approved);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
