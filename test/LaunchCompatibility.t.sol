// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictIMD} from "../src/VerdictIMD.sol";

/// @dev Local test helper only; not the production factory or pool manager.
contract FactoryHarness {
    function deploy(bytes32 salt) external returns (VerdictIMD) {
        return new VerdictIMD{salt: salt}();
    }

    function move(VerdictIMD token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

contract RejectingReceiver {
    fallback() external {
        revert("ERC-20 transfers must not call the recipient");
    }
}

contract LaunchCompatibilityTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    function test_Create2FactoryReceivesEntireSupplyWithoutConstructorConfiguration() public {
        FactoryHarness factory = new FactoryHarness();
        bytes32 salt = keccak256("factory launch test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            salt,
                            keccak256(type(VerdictIMD).creationCode)
                        )
                    )
                )
            )
        );
        VerdictIMD token = factory.deploy(salt);

        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Exercises token custody transfers only, not AMM pricing or liquidity accounting.
    function test_LaunchAllocationClaimAndPoolTransfersArriveWhole() public {
        FactoryHarness factory = new FactoryHarness();
        VerdictIMD token = factory.deploy(keccak256("allocation test"));
        address distributor = makeAddr("distributor");
        address poolCustodian = makeAddr("pool custodian");
        address requester = makeAddr("requester");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarm - pool;

        factory.move(token, distributor, swarm);
        factory.move(token, poolCustodian, pool);
        factory.move(token, requester, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolCustodian), pool);
        assertEq(token.balanceOf(requester), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarm);

        vm.prank(poolCustodian);
        assertTrue(token.transfer(trader, 100 ether));
        assertEq(token.balanceOf(trader), 100 ether);
        assertEq(token.balanceOf(poolCustodian), pool - 100 ether);
        vm.prank(trader);
        assertTrue(token.transfer(poolCustodian, 100 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolCustodian), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractDoesNotInvokeReceiver() public {
        VerdictIMD token = new VerdictIMD();
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 1 ether));
        assertEq(token.balanceOf(address(receiver)), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1 ether);
    }
}
